#include "AstCopier.h"

template<class T>
T visit(T node, AstCopier *t) {
    return (T) node->accept(t, nullptr);
}

void *AstCopier::visitLiteral(Literal *node, void *arg) {
    auto res = new Literal;
    res->val = node->val;
    res->type = node->type;
    return res;
}

void *AstCopier::visitSimpleName(SimpleName *node, void *arg) {
    return new SimpleName(node->name);
}

void *AstCopier::visitType(Type *node, void *arg) {
    auto ptr = dynamic_cast<PointerType *>(node);
    if (ptr) {
        auto inner = visit(ptr->type, this);
        auto res = new PointerType(inner);
        return res;
    }
    auto res = new Type;
    if (node->scope) res->scope = visit(node->scope, this);
    res->name = node->name;
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(visit(ta, this));
    }
    return res;
}

void *AstCopier::visitInfix(Infix *node, void *arg) {
    auto res = new Infix;
    res->left = visit(node->left, this);
    res->right = visit(node->right, this);
    res->op = node->op;
    return res;
}

void *AstCopier::visitBlock(Block *node, void *arg) {
    auto res = new Block;
    for (auto st : node->list) {
        res->list.push_back(visit(st, this));
    }
    return res;
}

void *AstCopier::visitReturnStmt(ReturnStmt *node, void *arg) {
    auto res = new ReturnStmt;
    if (node->expr) {
        res->expr = visit(node->expr, this);
    }
    return res;
}

void *AstCopier::visitVarDecl(VarDecl *node, void *arg) {
    auto res = new VarDecl;
    res->decl = visit(node->decl, this);
    return res;
}

void *AstCopier::visitVarDeclExpr(VarDeclExpr *node, void *arg) {
    auto res = new VarDeclExpr;
    res->isConst = node->isConst;
    res->isStatic = node->isStatic;
    for (auto f : node->list) {
        res->list.push_back(visit(f, this));
    }
    return res;
}

void *AstCopier::visitFragment(Fragment *node, void *arg) {
    auto res = new Fragment;
    res->name = node->name;
    if (node->type) {
        res->type = visit(node->type, this);
    }
    res->rhs = visit(node->rhs, this);
    res->isOptional = node->isOptional;
    return res;
}

void *AstCopier::visitObjExpr(ObjExpr *node, void *arg) {
    auto res = new ObjExpr;
    res->isPointer = node->isPointer;
    res->type = visit(node->type, this);
    for (auto &e : node->entries) {
        auto ent = Entry();
        ent.key = e.key;
        ent.value = visit(e.value, this);
        res->entries.push_back(ent);
    }
    return res;
}

void *AstCopier::visitMethodCall(MethodCall *node, void *arg) {
    auto res = new MethodCall;
    res->isOptional = node->isOptional;
    if (node->scope) {
        res->scope = visit(node->scope, this);
    }
    res->name = node->name;
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(visit(ta, this));
    }
    for (auto arg : node->args) {
        res->args.push_back(visit(arg, this));
    }
    return res;
}
