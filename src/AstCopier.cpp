#include "AstCopier.h"

Statement *visit(Statement *node, AstCopier *t) {
    auto res = node->accept(t);
    return std::any_cast<Statement *>(res);
}
Statement *visit(std::unique_ptr<Statement> &node, AstCopier *t) {
    auto res = node->accept(t);
    return std::any_cast<Statement *>(res);
}

template<typename T>
T *visit0(std::unique_ptr<T> &node, AstCopier *t) {
    auto res = node->accept(t);
    return std::any_cast<T *>(res);
}
template<typename T>
T visit0(T node, AstCopier *t) {
    auto res = node->accept(t);
    return std::any_cast<T>(res);
}

template<typename T>
T visit1(T node, AstCopier *t) {
    auto res = node->accept(t);
    auto st = std::any_cast<Statement *>(res);
    return (T) st;
}

std::any AstCopier::visitLiteral(Literal *node) {
    auto res = new Literal(node->type, node->val);
    if (node->suffix) {
        res->suffix.reset(visit0(node->suffix, this));
    }
    return (Expression *)res;
}

std::any AstCopier::visitSimpleName(SimpleName *node) {
    return (Expression *)new SimpleName(node->name);
}

std::any AstCopier::visitType(Type *node) {
    if (node->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(node);
        auto inner = visit0(ptr->type, this);
        return new PointerType(inner);
    }
    if (node->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(node);
        auto inner = visit0(arr->type, this);
        return new ArrayType(inner, arr->size);
    }
    if (node->isSlice()) {
        auto slice = dynamic_cast<SliceType *>(node);
        auto inner = visit0(slice->type, this);
        return new SliceType(inner);
    }
    auto res = new Type;
    if (node->scope) res->scope = visit0(node->scope, this);
    res->name = node->name;
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(visit0(ta, this));
    }
    return (Expression *)res;
}

std::any AstCopier::visitInfix(Infix *node) {
    auto res = new Infix;
    res->left = visit0(node->left, this);
    res->right = visit0(node->right, this);
    res->op = node->op;
    return (Expression *)res;
}

std::any AstCopier::visitBlock(Block *node) {
    auto res = new Block;
    for (auto &st : node->list) {
        res->list.push_back(std::unique_ptr<Statement>(visit(st, this)));
    }
    return (Statement *) res;
}

std::any AstCopier::visitReturnStmt(ReturnStmt *node) {
    auto res = new ReturnStmt;
    if (node->expr) {
        res->expr.reset(visit0(node->expr, this));
    }
    return (Statement *) res;
}

std::any AstCopier::visitVarDecl(VarDecl *node) {
    auto res = new VarDecl;
    res->decl = visit1(node->decl, this);
    return (Statement *) res;
}

std::any AstCopier::visitVarDeclExpr(VarDeclExpr *node) {
    auto res = new VarDeclExpr;
    res->isConst = node->isConst;
    res->isStatic = node->isStatic;
    for (auto f : node->list) {
        res->list.push_back(visit0(f, this));
    }
    return (Statement *) res;
}

std::any AstCopier::visitFragment(Fragment *node) {
    auto res = new Fragment;
    res->name = node->name;
    if (node->type) {
        res->type.reset(visit0(node->type, this));
    }
    res->rhs.reset(visit0(node->rhs, this));
    res->isOptional = node->isOptional;
    return res;
}

std::any AstCopier::visitObjExpr(ObjExpr *node) {
    auto res = new ObjExpr;
    res->isPointer = node->isPointer;
    res->type.reset(visit0(node->type, this));
    for (auto &e : node->entries) {
        auto ent = Entry();
        ent.key = e.key;
        ent.value = visit0(e.value, this);
        res->entries.push_back(ent);
    }
    return (Expression *)res;
}

std::any AstCopier::visitMethodCall(MethodCall *node) {
    auto res = new MethodCall;
    res->isOptional = node->isOptional;
    if (node->scope) {
        res->scope.reset(visit0(node->scope.get(), this));
    }
    res->name = node->name;
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(visit0(ta, this));
    }
    for (auto arg : node->args) {
        res->args.push_back(visit0(arg, this));
    }
    return (Expression *)res;
}
std::any AstCopier::visitExprStmt(ExprStmt *node) {
    auto tmp = visit0(node->expr, this);
    return (Statement *) new ExprStmt(tmp);
}
std::any AstCopier::visitAssign(Assign *node) {
    auto res = new Assign;
    res->left = visit0(node->left, this);
    res->right = visit0(node->right, this);
    res->op = node->op;
    return (Expression *)res;
}

std::any AstCopier::visitArrayAccess(ArrayAccess *node) {
    auto res = new ArrayAccess;
    res->array = visit0(node->array, this);
    res->index = visit0(node->index, this);
    if (node->index2) {
        res->index2.reset(visit0(node->index2.get(), this));
    }
    return (Expression *)res;
}
std::any AstCopier::visitFieldAccess(FieldAccess *node) {
    auto res = new FieldAccess;
    res->scope = visit0(node->scope, this);
    res->name = node->name;
    return (Expression *)res;
}

std::any AstCopier::visitUnary(Unary *node) {
    auto res = new Unary;
    res->op = node->op;
    res->expr = visit0(node->expr, this);
    return (Expression *) res;
}

std::any AstCopier::visitWhileStmt(WhileStmt *node) {
    auto res = new WhileStmt;
    res->expr.reset(visit0(node->expr.get(), this));
    res->body.reset(visit0(node->body.get(), this));
    return (Statement *) res;
}
std::any AstCopier::visitIfStmt(IfStmt *node) {
    auto res = new IfStmt;
    res->expr.reset(visit0(node->expr.get(), this));
    res->thenStmt.reset(visit(node->thenStmt.get(), this));
    if (node->elseStmt) {
        res->elseStmt.reset(visit(node->elseStmt.get(), this));
    }
    return (Statement *) res;
}

std::any AstCopier::visitIfLetStmt(IfLetStmt *node) {
    auto res = new IfLetStmt;
    res->type.reset(visit0(node->type.get(), this));
    for (auto a : node->args) {
        res->args.push_back(a);
    }
    res->rhs.reset(visit0(node->rhs.get(), this));
    res->thenStmt.reset(visit(node->thenStmt.get(), this));
    if (node->elseStmt) {
        res->elseStmt.reset(visit(node->elseStmt.get(), this));
    }
    return (Statement *) res;
}

std::any AstCopier::visitMethod(Method *node) {
    auto res = new Method(node->unit);
    res->name = node->name;
    res->type.reset(visit0(node->type.get(), this));
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(visit0(ta, this));
    }
    if (node->self) {
        auto self = new Param;
        self->name = node->self->name;
        if (node->self->type) {
            self->type.reset(visit0(node->self->type.get(), this));
        }
        self->method = res;
        res->self.reset(self);
    }
    for (auto &prm : node->params) {
        auto param = new Param;
        param->name = prm->name;
        param->type.reset(visit0(prm->type.get(), this));
        param->method = res;
        res->params.push_back(std::unique_ptr<Param>(param));
    }
    auto body = visit(node->body.get(), this);
    res->body.reset((Block *) std::any_cast<Statement *>(body));

    return res;
}