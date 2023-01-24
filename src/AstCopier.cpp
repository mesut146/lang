#include "AstCopier.h"

template<class T>
T visit(T node, AstCopier *t) {
    return (T) node->accept(t);
}

template<class T>
T *visit(std::unique_ptr<T> &node, AstCopier *t) {
    return (T *) node->accept(t);
}

void *AstCopier::visitLiteral(Literal *node) {
    auto res = new Literal;
    res->val = node->val;
    res->type = node->type;
    return res;
}

void *AstCopier::visitSimpleName(SimpleName *node) {
    return new SimpleName(node->name);
}

void *AstCopier::visitType(Type *node) {
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

void *AstCopier::visitInfix(Infix *node) {
    auto res = new Infix;
    res->left = visit(node->left, this);
    res->right = visit(node->right, this);
    res->op = node->op;
    return res;
}

void *AstCopier::visitBlock(Block *node) {
    auto res = new Block;
    for (auto &st : node->list) {
        res->list.push_back(std::unique_ptr<Statement>(visit(st, this)));
    }
    return res;
}

void *AstCopier::visitReturnStmt(ReturnStmt *node) {
    auto res = new ReturnStmt;
    if (node->expr) {
        res->expr.reset(visit(node->expr, this));
    }
    return res;
}

void *AstCopier::visitVarDecl(VarDecl *node) {
    auto res = new VarDecl;
    res->decl = visit(node->decl, this);
    return res;
}

void *AstCopier::visitVarDeclExpr(VarDeclExpr *node) {
    auto res = new VarDeclExpr;
    res->isConst = node->isConst;
    res->isStatic = node->isStatic;
    for (auto f : node->list) {
        res->list.push_back(visit(f, this));
    }
    return res;
}

void *AstCopier::visitFragment(Fragment *node) {
    auto res = new Fragment;
    res->name = node->name;
    if (node->type) {
        res->type.reset(visit(node->type, this));
    }
    res->rhs.reset(visit(node->rhs, this));
    res->isOptional = node->isOptional;
    return res;
}

void *AstCopier::visitObjExpr(ObjExpr *node) {
    auto res = new ObjExpr;
    res->isPointer = node->isPointer;
    res->type.reset(visit(node->type, this));
    for (auto &e : node->entries) {
        auto ent = Entry();
        ent.key = e.key;
        ent.value = visit(e.value, this);
        res->entries.push_back(ent);
    }
    return res;
}

void *AstCopier::visitMethodCall(MethodCall *node) {
    auto res = new MethodCall;
    res->isOptional = node->isOptional;
    if (node->scope) {
        res->scope.reset(visit(node->scope.get(), this));
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
void *AstCopier::visitExprStmt(ExprStmt *node) {
    auto tmp = visit(node->expr, this);
    return new ExprStmt(tmp);
}
void *AstCopier::visitAssign(Assign *node) {
    auto res = new Assign;
    res->left = visit(node->left, this);
    res->right = visit(node->right, this);
    res->op = node->op;
    return res;
}

void *AstCopier::visitArrayAccess(ArrayAccess *node) {
    auto res = new ArrayAccess;
    res->array = visit(node->array, this);
    res->index = visit(node->index, this);
    return res;
}
void *AstCopier::visitFieldAccess(FieldAccess *node) {
    auto res = new FieldAccess;
    res->scope = visit(node->scope, this);
    res->name = node->name;
    return res;
}

void *AstCopier::visitUnary(Unary *node) {
    auto res = new Unary;
    res->op = node->op;
    res->expr = visit(node->expr, this);
    return res;
}

void *AstCopier::visitWhileStmt(WhileStmt *node) {
    auto res = new WhileStmt;
    res->expr.reset(visit(node->expr.get(), this));
    res->body.reset(visit(node->body.get(), this));
    return res;
}
void *AstCopier::visitIfStmt(IfStmt *node) {
    auto res = new IfStmt;
    res->expr.reset(visit(node->expr.get(), this));
    res->thenStmt.reset(visit(node->thenStmt.get(), this));
    if (node->elseStmt) {
        res->elseStmt.reset(visit(node->elseStmt.get(), this));
    }
    return res;
}

void *AstCopier::visitMethod(Method *node) {
    auto res = new Method(node->unit);
    res->name = node->name;
    res->type.reset(visit(node->type.get(), this));
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(visit(ta, this));
    }
    if(node->self){
        auto self = new Param;
        self->name = node->self->name;
        if(node->self->type)
        self->type.reset(visit(node->self->type.get(), this));
        self->method = res;
        res->self.reset(self);
    }
    for (auto prm : node->params) {
        auto param = new Param;
        param->name = prm->name;
        param->type.reset(visit(prm->type.get(), this));
        param->method = res;
        res->params.push_back(param);
    }
    res->body.reset(visit(node->body.get(), this));

    return res;
}