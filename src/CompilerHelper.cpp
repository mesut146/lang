#include "Compiler.h"
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>

bool doesAlloc(Expression *e) {
    auto obj = dynamic_cast<ObjExpr *>(e);
    if (obj) {
        return !obj->isPointer;
    }
    auto aa = dynamic_cast<ArrayAccess *>(e);
    if (aa) {
        return aa->index2.get() != nullptr;
    }
    auto lit = dynamic_cast<Literal *>(e);
    if (lit) {
        return lit->type == Literal::STR;
    }
    return dynamic_cast<Type *>(e) || dynamic_cast<ArrayExpr *>(e);
}

bool isStrLit(Expression *e) {
    auto l = dynamic_cast<Literal *>(e);
    if (!l) return false;
    return l->type == Literal::STR;
}

//llvm

llvm::ConstantInt *Compiler::makeInt(int val, int bits) {
    auto intType = llvm::IntegerType::get(ctx, bits);
    return llvm::ConstantInt::get(intType, val);
}

llvm::ConstantInt *Compiler::makeInt(int val) {
    return makeInt(val, 32);
}

llvm::Type *Compiler::getInt(int bit) {
    return llvm::IntegerType::get(ctx, bit);
}

void Compiler::simpleVariant(Type *n, llvm::Value *ptr) {
    auto bd = resolv->resolve(n->scope.get()).targetDecl;
    auto decl = dynamic_cast<EnumDecl *>(bd);
    int index = Resolver::findVariant(decl, n->name);
    setOrdinal(index, ptr);
}
void Compiler::setOrdinal(int index, llvm::Value *ptr) {
    auto ordPtr = Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, 0);
    Builder->CreateStore(makeInt(index), ordPtr);
}

llvm::Function *Compiler::make_printf() {
    std::vector<llvm::Type *> args;
    auto charPtr = getInt(8)->getPointerTo();
    args.push_back(charPtr);
    auto ft = llvm::FunctionType::get(getInt(32), args, true);
    auto f = llvm::Function::Create(ft, llvm::Function::ExternalLinkage, "printf", *mod);
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    return f;
}

llvm::Function *Compiler::make_exit() {
    auto ft = llvm::FunctionType::get(Builder->getVoidTy(), getInt(32), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "exit", *mod);
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    return f;
}

llvm::Function *Compiler::make_malloc() {
    auto ret = getInt(8)->getPointerTo();//i8*
    auto ft = llvm::FunctionType::get(ret, getInt(64), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "malloc", *mod);
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    llvm::AttrBuilder builder;
    builder.addAlignmentAttr(16);
    attr = attr.addAttributes(ctx, 0, builder);
    f->setAttributes(attr);
    return f;
}

llvm::StructType *Compiler::make_slice_type() {
    std::vector<llvm::Type *> elems;
    elems.push_back(getInt(8)->getPointerTo());
    elems.push_back(getInt(32));//len
    return llvm::StructType::create(ctx, elems, "__slice");
}

llvm::StructType *Compiler::make_string_type() {
    std::vector<llvm::Type *> elems={sliceType};
    return llvm::StructType::create(ctx, elems, "str");
}

llvm::Type *Compiler::mapType(Type *type) {
    if (type->isPointer()) {
        auto elem = dynamic_cast<PointerType *>(type)->type;
        if (isStruct(elem)) {
            //forward
        }
        return mapType(elem)->getPointerTo();
    }
    if (type->isArray()) {
        auto res = resolv->getType(type);
        auto arr = dynamic_cast<ArrayType *>(res);
        return llvm::ArrayType::get(mapType(arr->type), arr->size);
    }
    if (type->isSlice()) {
        return sliceType;
    }
    if (type->isString()) {
        return stringType;
    }
    if (type->isVoid()) {
        return llvm::Type::getVoidTy(ctx);
    }
    if (type->isPrim()) {
        auto bits = sizeMap[type->name];
        return getInt(bits);
    }
    auto rt = resolv->resolve(type);
    //auto s = mangle(rt.targetDecl->type);
    auto s = rt.targetDecl->type->print();
    auto it = classMap.find(s);
    if (it != classMap.end()) {
        return it->second;
    }
    return makeDecl(rt.targetDecl);
    
    //throw std::runtime_error("mapType: " + s);
}

int Compiler::getSize(BaseDecl *decl) {
    if (decl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        int res = 0;
        for (auto ev : ed->variants) {
            if (ev->fields.empty()) continue;
            int cur = 0;
            for (auto &f : ev->fields) {
                cur += getSize(f->type);
            }
            res = cur > res ? cur : res;
        }
        return res;
    } else {
        auto td = dynamic_cast<StructDecl *>(decl);
        int res = 0;
        for (auto &fd : td->fields) {
            res += getSize(fd->type);
        }
        return res;
    }
}

int Compiler::getSize(Type *type) {
    if (type->isPointer()) {
        return 64;
    }
    if (type->isPrim()) {
        return sizeMap[type->name];
    }
    if (type->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(type);
        return getSize(arr->type) * arr->size;
    }
    if (type->isSlice()) {
        //ptr + len
        return 64 + 32;
    }

    auto decl = resolv->resolve(type).targetDecl;
    if (decl) {
        return getSize(decl);
    }
    throw std::runtime_error("size(" + type->print() + ")");
}

class AllocCollector : public Visitor {
public:
    Compiler *compiler;

    AllocCollector(Compiler *c) : compiler(c) {}

    llvm::Value *alloca(llvm::Type *ty) {
        auto ptr = compiler->Builder->CreateAlloca(ty);
        compiler->allocArr.push_back(ptr);
        return ptr;
    }
    std::any visitVarDecl(VarDecl *node) override {
        node->decl->accept(this);
        return {};
    }
    std::any visitVarDeclExpr(VarDeclExpr *node) override {
        for (auto f : node->list) {
            auto type = f->type ? f->type.get() : compiler->resolv->getType(f->rhs.get());
            llvm::Value *ptr;
            if (doesAlloc(f->rhs.get())) {
                //auto alloc
                auto rhs = f->rhs->accept(this);
                ptr = std::any_cast<llvm::Value *>(rhs);
            } else {
                //manual alloc, prims, struct copy
                auto ty = compiler->mapType(type);
                ptr = alloca(ty);
                if(dynamic_cast<MethodCall*>(f->rhs.get())){
                    //todo not just this
                    f->rhs->accept(this);
                }
            }
            ptr->setName(f->name);
            compiler->NamedValues[f->name] = ptr;
        }
        return {};
    }
    std::any visitType(Type *node) override {
        if (!node->scope) {
            return {};
        }
        //todo
        if (node->isPointer()) {
            return {};
        }
        auto ty = compiler->mapType(node->scope.get());
        auto ptr = alloca(ty);
        return ptr;
    }
    std::any visitObjExpr(ObjExpr *node) override {
        if (node->isPointer) {
            //todo this too
            return {};
        }
        auto ty = compiler->mapType(compiler->resolv->getType(node));
        return alloca(ty);
    }
    std::any visitArrayExpr(ArrayExpr *node) {
        auto r = compiler->resolv->getType(node);
        auto ty = compiler->mapType(r);
        auto ptr = alloca(ty);
        for (auto e : node->list) {
            auto mc = dynamic_cast<MethodCall *>(e);
            if (mc) {
                //throw std:: runtime_error("mc to array");
            } else {
                //e->accept(this);
            }
        }
        return ptr;
    }
    std::any visitArrayAccess(ArrayAccess *node) {
        if (node->index2) {
            auto ptr = alloca(compiler->sliceType);
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
    std::any visitLiteral(Literal *node) {
        if (node->type == Literal::STR) {
            return alloca(compiler->stringType);
        }
        return {};
    }
    std::any visitBlock(Block *node) override {
        for (auto &s : node->list) {
            s->accept(this);
        }
        return {};
    }
    std::any visitWhileStmt(WhileStmt *node) override {
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
        node->thenStmt->accept(this);
        if (node->elseStmt) {
            node->elseStmt->accept(this);
        }
        return {};
    }
    std::any visitReturnStmt(ReturnStmt *node) override {
        if (node->expr) {
            node->expr->accept(this);
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
    std::any visitInfix(Infix *node) {
        node->left->accept(this);
        node->right->accept(this);
        return {};
    }
    std::any visitAssertStmt(AssertStmt *node) {
        node->expr->accept(this);
        return {};
    }

    std::any visitRefExpr(RefExpr *node) {
        node->expr->accept(this);
        return {};
    }
    std::any visitDerefExpr(DerefExpr *node) {
        node->expr->accept(this);
        return {};
    }
    std::any visitUnary(Unary *node) {
        node->expr->accept(this);
        return {};
    }
    std::any visitMethodCall(MethodCall *node) {
        if (node->scope) node->scope->accept(this);
        for (auto a : node->args) {
            if (!node->scope && node->name == "print" && isStrLit(a)) {
                continue;
            }
            a->accept(this);
        }
        return {};
    }
    std::any visitFieldAccess(FieldAccess *node) {
        node->scope->accept(this);
        return {};
    }
    std::any visitParExpr(ParExpr *node) {
        node->expr->accept(this);
        return {};
    }
    std::any visitAsExpr(AsExpr *node) {
        node->expr->accept(this);
        return {};
    }
    std::any visitIsExpr(IsExpr *node) {
        node->expr->accept(this);
        return {};
    }
    std::any visitIfLetStmt(IfLetStmt *node) {
        node->rhs->accept(this);
        node->thenStmt->accept(this);
        if (node->elseStmt) node->elseStmt->accept(this);
        return {};
    }
    std::any visitContinueStmt(ContinueStmt *node) {
        return {};
    }
    std::any visitBreakStmt(BreakStmt *node) {
        return {};
    }
};

void Compiler::makeLocals(Statement *st) {
    allocIdx = 0;
    allocArr.clear();
    if(st){
      AllocCollector col(this);
      st->accept(&col);
    }
}