#include "Compiler.h"

class AllocCollector : public Visitor {
public:
    Compiler *compiler;

    AllocCollector(Compiler *c) : compiler(c) {}

    void set_alloc(Node *node, llvm::Value *ptr) {
        if (node->id == -1) {
            throw std::runtime_error("set_alloc() id -1 for " + node->print());
        }
        if (ptr == nullptr) {
            throw std::runtime_error("set_alloc() null ptr for " + node->print());
        }
        if (compiler->allocMap2.contains(node->id)) {
            throw std::runtime_error("set_alloc() double alloc for " + node->print());
        }
        compiler->allocMap2[node->id] = ptr;
    }

    llvm::Value *alloc(llvm::Type *type, Node *e) {
        auto ptr = compiler->Builder->CreateAlloca(type);
        set_alloc(e, ptr);
        return ptr;
    }
    llvm::Value *alloc(const Type &type, Node *e) {
        return alloc(compiler->mapType(type), e);
    }
    std::any visitVarDecl(VarDecl *node) override {
        node->decl->accept(this);
        return {};
    }
    std::any visitVarDeclExpr(VarDeclExpr *node) override {
        for (auto &f : node->list) {
            auto rhs = f.rhs.get();
            auto type = f.type ? compiler->resolv->resolve(*f.type) : compiler->resolv->resolve(rhs);
            llvm::Value *ptr;
            if (compiler->doesAlloc(rhs)) {
                //auto alloc
                auto rhs2 = f.rhs->accept(this);
                ptr = std::any_cast<llvm::Value *>(rhs2);
                set_alloc(&f, ptr);
            } else {
                //manual alloc, prims, struct copy
                ptr = alloc(type.type, &f);
                f.rhs->accept(this);
            }
            ptr->setName(f.name);
        }
        return {};
    }
    void call(MethodCall *node) {
        if (is_std_parent_name(node)) {
            alloc(Type("str"), node);
            return;
        }
        if (is_format(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            //todo uncomment below
            //info.unwrap_mc.accept(this);
            alloc(Type("String"), node);
            return;
        }
        if (is_print(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            return;
        }
        if (is_panic(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            return;
        }
        //todo rvo
        if (node->scope) {
            node->scope->accept(this);
        }
        for (auto a : node->args) {
            a->accept(this);
        }
    }

    std::any visitMethodCall(MethodCall *node) override {
        if(Resolver::is_std_zeroed(node)){
            auto ty = node->typeArgs.at(0);
            return alloc(ty, node);
        }
        if (is_std_parent_name(node)) {
            return alloc(Type("str"), node);
        }
        if (is_format(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            //todo uncomment below
            //info.unwrap_mc.accept(this);
            return alloc(Type("String"), node);
        }
        if (is_print(node) || is_assert(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            return {};
        }
        if (is_panic(node)) {
            auto &info = compiler->resolv->format_map.at(node->id);
            info.block.accept(this);
            return {};
        }
        auto m = compiler->resolv->resolve(node).targetMethod;
        llvm::Value *ptr = nullptr;
        if (m && compiler->isRvo(m)) {
            ptr = alloc(m->type, node);
        }
        //do need coercion to ptr, rvalue to local conv
        if (m) {
            auto rval = RvalueHelper::need_alloc(node, m, compiler->resolv.get());
            if (rval.rvalue) {
                alloc(rval.scope_type, rval.scope);
            }
        }
        if (node->scope) node->scope->accept(this);
        for (auto a : node->args) {
            a->accept(this);
        }
        return ptr;
    }
    std::any visitType(Type *node) override {
        if (!node->scope) {
            return {};
        }
        if (node->isPointer()) {
            return {};
        }
        return alloc(*node, node);
    }

    void child(Expression *e) {
        auto mc = dynamic_cast<MethodCall *>(e);
        if (mc) {
            if (Config::rvo_ptr) call(mc);
            else
                e->accept(this);
            return;
        }
        auto obj = dynamic_cast<ObjExpr *>(e);
        if (obj) {
            for (auto &ent : obj->entries) {
                if (!ent.isBase) child(ent.value);
            }
            return;
        }
        auto ty = dynamic_cast<Type *>(e);
        if (ty) {
            return;
        }
        auto ae = dynamic_cast<ArrayExpr *>(e);
        if (ae) {
            return;
        }
        auto aa = dynamic_cast<ArrayAccess *>(e);
        if (aa && aa->index2) {
            aa->array->accept(this);
        }
    }
    void object(ObjExpr *node) {
        for (auto &e : node->entries) {
            if (!e.isBase) child(e.value);
        }
    }
    std::any visitObjExpr(ObjExpr *node) override {
        auto ty = compiler->resolv->getType(node);
        auto ptr = alloc(ty, node);
        for (auto &e : node->entries) {
            if (!e.isBase) child(e.value);
            else {
                child(e.value);
            }
        }
        return ptr;
    }
    std::any visitArrayExpr(ArrayExpr *node) override {
        auto ty = compiler->resolv->getType(node);
        auto ptr = alloc(ty, node);
        //((llvm::AllocaInst*)ptr)->setAlignment(llvm::Align(100));
        if (node->isSized() && compiler->doesAlloc(node->list[0])) {
            node->list[0]->accept(this);
        }
        return ptr;
    }
    std::any visitArrayAccess(ArrayAccess *node) override {
        if (node->index2) {
            auto ptr = alloc(compiler->sliceType, node);
            node->array->accept(this);
            node->index2->accept(this);
            node->index->accept(this);
            return ptr;
        } else {
            node->array->accept(this);
            node->index->accept(this);
        }
        return {};
    }
    std::any visitLiteral(Literal *node) override {
        if (node->type == Literal::STR) {
            return alloc(compiler->stringType, node);
        }
        return {};
    }
    std::any visitFieldAccess(FieldAccess *node) override {
        node->scope->accept(this);
        return {};
    }
    std::any visitBlock(Block *node) override {
        for (auto &s : node->list) {
            s->accept(this);
        }
        return {};
    }
    std::any visitWhileStmt(WhileStmt *node) override {
        node->expr->accept(this);
        node->body->accept(this);
        return {};
    }
    std::any visitForStmt(ForStmt *node) override {
        if (node->decl) {
            node->decl->accept(this);
        }
        node->body->accept(this);
        return {};
    }
    std::any visitIfStmt(IfStmt *node) override {
        node->expr->accept(this);
        node->thenStmt->accept(this);
        if (node->elseStmt) {
            node->elseStmt->accept(this);
        }
        return {};
    }
    std::any visitReturnStmt(ReturnStmt *node) override {
        if (!node->expr) {
            return {};
        }
        auto e = node->expr.get();
        auto mc = dynamic_cast<MethodCall *>(e);
        if (mc) {
            call(mc);
            return {};
        }
        auto oe = dynamic_cast<ObjExpr *>(e);
        if (oe) {
            object(oe);
            return {};
        }
        if (compiler->doesAlloc(e)) {
            return {};
        } else {
            e->accept(this);
        }
        return {};
    }
    std::any visitExprStmt(ExprStmt *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitAssign(Assign *node) override {
        node->right->accept(this);
        return {};
    }
    std::any visitSimpleName(SimpleName *node) override {
        return {};
    }
    std::any visitInfix(Infix *node) override {
        node->left->accept(this);
        node->right->accept(this);
        return {};
    }

    std::any visitRefExpr(RefExpr *node) override {
        if (RvalueHelper::is_rvalue(node->expr.get())) {
            auto type = compiler->resolv->getType(node->expr.get());
            alloc(type, node);
        }
        node->expr->accept(this);
        return {};
    }
    std::any visitDerefExpr(DerefExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitUnary(Unary *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitParExpr(ParExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitAsExpr(AsExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitIsExpr(IsExpr *node) override {
        node->expr->accept(this);
        return {};
    }
    std::any visitIfLetStmt(IfLetStmt *node) override {
        node->rhs->accept(this);
        auto rhs_rt = compiler->resolv->resolve(node->type);
        auto decl = (EnumDecl *) rhs_rt.targetDecl;
        auto index = Resolver::findVariant(decl, node->type.name);
        auto &variant = decl->variants[index];
        int i = 0;
        for (auto &arg : node->args) {
            Type type = variant.fields[i].type;
            if (arg.ptr) {
                type = Type(Type::Pointer, type);
            }
            auto ptr = alloc(type, &arg);
            ptr->setName(arg.name);
            i++;
        }
        node->thenStmt->accept(this);
        if (node->elseStmt) {
            node->elseStmt->accept(this);
        }
        return {};
    }
    std::any visitContinueStmt(ContinueStmt *node) override {
        return {};
    }
    std::any visitBreakStmt(BreakStmt *node) override {
        return {};
    }
};

void Compiler::makeLocals(Statement *st) {
    //std::cout << "makeLocals " << resolv->unit->path << " " << curMethod->name << "\n";
    allocMap2.clear();
    if (st) {
        AllocCollector col(this);
        st->accept(&col);
    }
}