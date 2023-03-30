#include "AstCopier.h"

template<typename T>
std::unique_ptr<T> expr(std::unique_ptr<T> &node, AstCopier *t) {
    return std::unique_ptr<T>(expr(node.get(), t));
}
template<typename T>
T expr(T node, AstCopier *t) {
    auto res = node->accept(t);
    return (T) std::any_cast<Expression *>(res);
}
template<typename T>
T stmt(T node, AstCopier *t) {
    auto res = node->accept(t);
    auto st = std::any_cast<Statement *>(res);
    return (T) st;
}
template<typename T>
std::unique_ptr<T> stmt(std::unique_ptr<T> &node, AstCopier *t) {
    return std::unique_ptr<T>(stmt(node.get(), t));
}
template<typename T>
T visit(T node, AstCopier *t) {
    auto res = node->accept(t);
    auto st = std::any_cast<T>(res);
    return st;
}

Expression *loc(Expression *res, Expression *src) {
    res->line = src->line;
    return res;
}

Statement *loc(Statement *res, Statement *src) {
    res->line = src->line;
    return res;
}

std::any AstCopier::visitLiteral(Literal *node) {
    auto res = new Literal(node->type, node->val);
    if (node->suffix) {
        res->suffix = expr(node->suffix, this);
    }
    return loc(res, node);
}

std::any AstCopier::visitSimpleName(SimpleName *node) {
    return loc(new SimpleName(node->name), node);
}

std::any AstCopier::visitType(Type *node) {
    if (node->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(node);
        auto inner = expr(ptr->type, this);
        return (Expression *) new PointerType(inner);
    }
    if (node->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(node);
        auto inner = expr(arr->type, this);
        return (Expression *) new ArrayType(inner, arr->size);
    }
    if (node->isSlice()) {
        auto slice = dynamic_cast<SliceType *>(node);
        auto inner = expr(slice->type, this);
        return (Expression *) new SliceType(inner);
    }
    auto res = new Type;
    if (node->scope) res->scope = expr(node->scope, this);
    res->name = node->name;
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(expr(ta, this));
    }
    return loc(res, node);
}

std::any AstCopier::visitInfix(Infix *node) {
    auto res = new Infix;
    res->left = expr(node->left, this);
    res->right = expr(node->right, this);
    res->op = node->op;
    return loc(res, node);
}

std::any AstCopier::visitBlock(Block *node) {
    auto res = new Block;
    for (auto &st : node->list) {
        res->list.push_back(stmt(st, this));
    }
    return loc(res, node);
}

std::any AstCopier::visitReturnStmt(ReturnStmt *node) {
    auto res = new ReturnStmt;
    if (node->expr) {
        res->expr = expr(node->expr, this);
    }
    return loc(res, node);
}

std::any AstCopier::visitVarDecl(VarDecl *node) {
    auto res = new VarDecl;
    res->decl = stmt(node->decl, this);
    return loc(res, node);
}

std::any AstCopier::visitVarDeclExpr(VarDeclExpr *node) {
    auto res = new VarDeclExpr;
    res->isConst = node->isConst;
    res->isStatic = node->isStatic;
    for (auto &f : node->list) {
        auto fr = std::any_cast<Fragment *>(visitFragment(&f));
        res->list.push_back(std::move(*fr));
        delete fr;
    }
    return loc(res, node);
}

std::any AstCopier::visitFragment(Fragment *node) {
    auto res = new Fragment();
    res->name = node->name;
    if (node->type) {
        res->type = expr(node->type, this);
    }
    res->rhs = expr(node->rhs, this);
    res->isOptional = node->isOptional;
    res->line = node->line;
    return res;
}

std::any AstCopier::visitObjExpr(ObjExpr *node) {
    auto res = new ObjExpr;
    res->isPointer = node->isPointer;
    res->type = (expr(node->type, this));
    for (auto &e : node->entries) {
        auto ent = Entry();
        ent.key = e.key;
        ent.value = expr(e.value, this);
        res->entries.push_back(ent);
    }
    return loc(res, node);
}

std::any AstCopier::visitMethodCall(MethodCall *node) {
    auto res = new MethodCall;
    res->isOptional = node->isOptional;
    if (node->scope) {
        res->scope.reset(expr(node->scope.get(), this));
    }
    res->name = node->name;
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(expr(ta, this));
    }
    for (auto arg : node->args) {
        res->args.push_back(expr(arg, this));
    }
    return loc(res, node);
}
std::any AstCopier::visitExprStmt(ExprStmt *node) {
    auto tmp = expr(node->expr, this);
    return loc(new ExprStmt(tmp), node);
}
std::any AstCopier::visitAssign(Assign *node) {
    auto res = new Assign;
    res->left = expr(node->left, this);
    res->right = expr(node->right, this);
    res->op = node->op;
    return loc(res, node);
}

//deref
std::any AstCopier::visitDerefExpr(DerefExpr *node) {
    auto res = new DerefExpr(expr(node->expr, this));
    return loc(res, node);
}

std::any AstCopier::visitRefExpr(RefExpr *node) {
    auto res = new RefExpr(expr(node->expr, this));
    return loc(res, node);
}

std::any AstCopier::visitArrayAccess(ArrayAccess *node) {
    auto res = new ArrayAccess;
    res->array = expr(node->array, this);
    res->index = expr(node->index, this);
    if (node->index2) {
        res->index2.reset(expr(node->index2.get(), this));
    }
    return loc(res, node);
}
std::any AstCopier::visitFieldAccess(FieldAccess *node) {
    auto res = new FieldAccess;
    res->scope = expr(node->scope, this);
    res->name = node->name;
    return loc(res, node);
}

std::any AstCopier::visitUnary(Unary *node) {
    auto res = new Unary;
    res->op = node->op;
    res->expr = expr(node->expr, this);
    return loc(res, node);
}

std::any AstCopier::visitWhileStmt(WhileStmt *node) {
    auto res = new WhileStmt;
    res->expr.reset(expr(node->expr.get(), this));
    res->body.reset(stmt(node->body.get(), this));
    return loc(res, node);
}
std::any AstCopier::visitForStmt(ForStmt *node) {
    auto res = new ForStmt;
    res->decl.reset(stmt(node->decl.get(), this));
    res->cond.reset(expr(node->cond.get(), this));
    for (auto &u : node->updaters) {
        res->updaters.push_back(expr(u, this));
    }
    res->body.reset(stmt(node->body.get(), this));
    return loc(res, node);
}

std::any AstCopier::visitIfStmt(IfStmt *node) {
    auto res = new IfStmt;
    res->expr.reset(expr(node->expr.get(), this));
    res->thenStmt.reset(stmt(node->thenStmt.get(), this));
    if (node->elseStmt) {
        res->elseStmt.reset(stmt(node->elseStmt.get(), this));
    }
    return loc(res, node);
}

std::any AstCopier::visitIfLetStmt(IfLetStmt *node) {
    auto res = new IfLetStmt;
    res->type.reset(expr(node->type.get(), this));
    for (auto &a : node->args) {
        res->args.push_back(a);
    }
    res->rhs.reset(expr(node->rhs.get(), this));
    res->thenStmt.reset(stmt(node->thenStmt.get(), this));
    if (node->elseStmt) {
        res->elseStmt.reset(stmt(node->elseStmt.get(), this));
    }
    return loc(res, node);
}

std::any AstCopier::visitMethod(Method *node) {
    auto res = new Method(node->unit);
    res->name = node->name;
    res->type.reset(expr(node->type.get(), this));
    res->isVirtual = node->isVirtual;
    for (auto ta : node->typeArgs) {
        res->typeArgs.push_back(expr(ta, this));
    }
    if (node->self) {
        Param self;
        self.line = node->self->line;
        self.name = node->self->name;
        if (node->self->type) {
            self.type.reset(expr(node->self->type.get(), this));
        }
        res->self = std::move(self);
    }
    for (auto &prm : node->params) {
        Param param;
        param.line = prm.line;
        param.name = prm.name;
        param.type.reset(expr(prm.type.get(), this));
        res->params.push_back(std::move(param));
    }
    auto body = stmt(node->body.get(), this);
    res->body.reset(body);
    res->line = node->line;
    return res;
}