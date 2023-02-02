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
    auto intType = llvm::IntegerType::get(*ctx, bits);
    return llvm::ConstantInt::get(intType, val);
}

llvm::ConstantInt *Compiler::makeInt(int val) {
    return makeInt(val, 32);
}

llvm::Type *Compiler::getInt(int bit) {
    return llvm::IntegerType::get(*ctx, bit);
}

void Compiler::simpleVariant(Type *n, llvm::Value *ptr) {
    auto bd = resolv->resolve(n->scope)->targetDecl;
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
    auto f = llvm::Function::Create(ft, llvm::Function::ExternalLinkage, "printf", mod);
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    return f;
}

llvm::Function *Compiler::make_exit() {
    auto ft = llvm::FunctionType::get(Builder->getVoidTy(), getInt(32), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "exit", mod);
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    f->setAttributes(attr);
    return f;
}

llvm::Function *Compiler::make_malloc() {
    auto ret = getInt(8)->getPointerTo();//i8*
    auto ft = llvm::FunctionType::get(ret, getInt(64), false);
    auto f = llvm::Function::Create(ft, llvm::GlobalValue::ExternalLinkage, "malloc", mod);
    f->setCallingConv(llvm::CallingConv::C);
    llvm::AttributeList attr;
    llvm::AttrBuilder builder;
    builder.addAlignmentAttr(16);
    attr = attr.addAttributes(*ctx, 0, builder);
    f->setAttributes(attr);
    return f;
}

llvm::StructType *Compiler::make_slice_type() {
    std::vector<llvm::Type *> elems;
    elems.push_back(getInt(8)->getPointerTo());
    elems.push_back(getInt(32));//len
    return llvm::StructType::create(*ctx, elems, "__slice");
}

llvm::StructType *Compiler::make_string_type() {
    std::vector<llvm::Type *> elems;
    elems.push_back(sliceType);
    return llvm::StructType::create(*ctx, elems, "str");
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
        auto res = resolv->resolve(type);
        auto arr = dynamic_cast<ArrayType *>(res->type);
        return llvm::ArrayType::get(mapType(arr->type), arr->size);
    }
    if (type->isSlice()) {
        return sliceType;
    }
    if (type->isString()) {
        return stringType;
    }
    if (type->isVoid()) {
        return llvm::Type::getVoidTy(*ctx);
    }
    if (type->isPrim()) {
        auto bits = sizeMap[type->name];
        return getInt(bits);
    }
    auto rt = resolv->resolveType(type);
    auto s = mangle(rt->targetDecl->type);
    auto it = classMap.find(s);
    if (it != classMap.end()) {
        return it->second;
    }
    throw std::runtime_error("mapType: " + s);
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
    if (dynamic_cast<PointerType *>(type)) {
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
        //data ptr, len
        return 64 + 32;
    }

    auto decl = resolv->resolveType(type)->targetDecl;
    if (decl) {
        return getSize(decl);
    }
    throw std::runtime_error("size(" + type->print() + ")");
}

class AllocCollector : public Visitor {
public:
    Compiler *compiler;

    AllocCollector(Compiler *c) : compiler(c) {}

    auto alloca(llvm::Type *ty) {
        auto ptr = compiler->Builder->CreateAlloca(ty);
        compiler->allocArr.push_back(ptr);
        return ptr;
    }

    void *visitVarDecl(VarDecl *node) override {
        for (auto f : node->decl->list) {
            auto type = f->type ? f->type.get() : compiler->resolv->resolve(f->rhs.get())->type;
            llvm::Value *ptr;
            if (doesAlloc(f->rhs.get())) {
                //auto alloc
                ptr = (llvm::Value *) f->rhs->accept(this);
            } else {
                //manual alloc, prims, struct copy
                auto ty = compiler->mapType(type);
                ptr = compiler->Builder->CreateAlloca(ty);
                compiler->allocArr.push_back(ptr);
            }
            ptr->setName(f->name);
            compiler->NamedValues[f->name] = ptr;
        }
        return nullptr;
    }
    void *visitType(Type *node) override {
        if (!node->scope) {
            return nullptr;
        }
        //todo
        if (node->isPointer()) {
            return nullptr;
        }
        auto r = compiler->resolv->resolve(node);
        auto ty = compiler->mapType(node->scope);
        auto ptr = compiler->Builder->CreateAlloca(ty, (unsigned) 0);
        compiler->allocArr.push_back(ptr);
        return ptr;
    }
    void *visitObjExpr(ObjExpr *node) override {
        if (node->isPointer) {
            //todo this too
            return nullptr;
        }
        auto ty = compiler->mapType(compiler->resolv->resolve(node)->type);
        return alloca(ty);
    }
    void *visitArrayExpr(ArrayExpr *node) {
        auto r = compiler->resolv->resolve(node);
        auto ty = compiler->mapType(r->type);
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
    void *visitArrayAccess(ArrayAccess *node) {
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
        return nullptr;
    }
    void *visitLiteral(Literal *node) {
        if (node->type == Literal::STR) {
            return alloca(compiler->stringType);
        }
        return nullptr;
    }
    void *visitBlock(Block *node) override {
        for (auto &s : node->list) {
            s->accept(this);
        }
        return nullptr;
    }
    void *visitWhileStmt(WhileStmt *node) override {
        node->body->accept(this);
        return nullptr;
    }
    void *visitIfStmt(IfStmt *node) override {
        node->thenStmt->accept(this);
        if (node->elseStmt) {
            node->elseStmt->accept(this);
        }
        return nullptr;
    }
    void *visitReturnStmt(ReturnStmt *node) override {
        if (node->expr) {
            node->expr->accept(this);
        }
        return nullptr;
    }
    void *visitExprStmt(ExprStmt *node) override {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitAssign(Assign *node) override {
        node->right->accept(this);
        return nullptr;
    }
    void *visitSimpleName(SimpleName *node) override {
        return nullptr;
    }
    void *visitInfix(Infix *node) {
        node->left->accept(this);
        node->right->accept(this);
        return nullptr;
    }
    void *visitAssertStmt(AssertStmt *node) {
        node->expr->accept(this);
        return nullptr;
    }

    void *visitRefExpr(RefExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitDerefExpr(DerefExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitUnary(Unary *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitMethodCall(MethodCall *node) {
        if (node->scope) node->scope->accept(this);
        for (auto a : node->args) {
            if (!node->scope && node->name == "print" && isStrLit(a)) {
                continue;
            }
            a->accept(this);
        }
        return nullptr;
    }
    void *visitFieldAccess(FieldAccess *node) {
        node->scope->accept(this);
        return nullptr;
    }
    void *visitParExpr(ParExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitAsExpr(AsExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitIsExpr(IsExpr *node) {
        node->expr->accept(this);
        return nullptr;
    }
    void *visitIfLetStmt(IfLetStmt *node) {
        node->rhs->accept(this);
        node->thenStmt->accept(this);
        if (node->elseStmt) node->elseStmt->accept(this);
        return nullptr;
    }
    void *visitContinueStmt(ContinueStmt *node) {
        return nullptr;
    }
    void *visitBreakStmt(BreakStmt *node) {
        return nullptr;
    }
};

void Compiler::makeLocals(Statement *st) {
    allocIdx = 0;
    allocArr.clear();
    AllocCollector col(this);
    st->accept(&col);
}