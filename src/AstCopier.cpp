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
T *visit(T *node, AstCopier *t) {
    auto res = node->accept(t);
    return std::any_cast<T *>(res);
}
template<typename T>
T visit(T &node, AstCopier *t) {
    auto res = node.accept(t);
    return std::any_cast<T>(res);
}

Type visit(Type &node, AstCopier *t) {
    auto res = node.accept(t);
    return *(Type *) std::any_cast<Expression *>(res);
}

Expression *loc(Expression *res, Expression *src) {
    res->line = src->line;
    res->id = ++Node::last_id;
    return res;
}

Statement *loc(Statement *res, Statement *src) {
    res->line = src->line;
    //res->id = ++Node::last_id;
    return res;
}

std::any AstCopier::visitLiteral(Literal *node) {
    auto res = new Literal(node->type, node->val);
    if (node->suffix) {
        res->suffix.emplace(visit(*node->suffix, this));
    }
    return loc(res, node);
}

std::any AstCopier::visitSimpleName(SimpleName *node) {
    return loc(new SimpleName(node->name), node);
}

std::any AstCopier::visitType(Type *node) {
    if (node->isPointer()) {
        auto inner = expr(node->scope.get(), this);
        return (Expression *) new Type(Type::Pointer, *inner);
    }
    if (node->isArray()) {
        auto inner = expr(node->scope.get(), this);
        return (Expression *) new Type(*inner, node->size);
    }
    if (node->isSlice()) {
        auto inner = expr(node->scope.get(), this);
        return (Expression *) new Type(Type::Slice, *inner);
    }
    auto res = new Type(node->name);
    if (node->scope) {
        res->scope.reset(expr(node->scope.get(), this));
    }
    for (auto &ta : node->typeArgs) {
        res->typeArgs.push_back(visit(ta, this));
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
    for (auto &f : node->list) {
        auto fr = std::any_cast<Fragment *>(visitFragment(&f));
        res->list.push_back(std::move(*fr));
        delete fr;
    }
    return loc(res, node);
}

std::any AstCopier::visitFragment(Fragment *node) {
    auto res = new Fragment();
    res->id = ++Node::last_id;
    res->line = node->line;
    res->name = node->name;
    if (node->type) {
        res->type = visit(*node->type, this);
    }
    res->rhs = expr(node->rhs, this);
    return res;
}

std::any AstCopier::visitObjExpr(ObjExpr *node) {
    auto res = new ObjExpr;
    res->type = visit(node->type, this);
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
    res->is_static = node->is_static;
    if (node->scope) {
        res->scope.reset(expr(node->scope.get(), this));
    }
    res->name = node->name;
    for (auto &ta : node->typeArgs) {
        res->typeArgs.push_back(visit(ta, this));
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

std::any AstCopier::visitParExpr(ParExpr *node){
    auto res = new ParExpr;
    res->expr = expr(node->expr, this);
    return loc(res, node);
}

std::any AstCopier::visitUnary(Unary *node) {
    auto res = new Unary;
    res->op = node->op;
    res->expr = expr(node->expr, this);
    return loc(res, node);
}
std::any AstCopier::visitAsExpr(AsExpr *node) {
    auto res = new AsExpr;
    res->expr = expr(node->expr, this);
    res->type = visit(node->type, this);
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
    res->type = visit(node->type, this);
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
    auto res = new Method(node->path);
    res->name = node->name;
    res->type = visit(node->type, this);
    res->isVirtual = node->isVirtual;
    for (auto &ta : node->typeArgs) {
        res->typeArgs.push_back(visit(ta, this));
    }
    if (node->self) {
        Param self(node->self->name);
        self.id = ++Node::last_id;
        self.line = node->self->line;
        self.is_deref = node->self->is_deref;
        if (node->self->type) {
            self.type.emplace(visit(*node->self->type, this));
        }
        res->self.emplace(self);//std::move(self);
    }
    for (auto &prm : node->params) {
        Param param(prm.name, visit(*prm.type, this));
        param.id = ++Node::last_id;
        param.line = prm.line;
        res->params.push_back(std::move(param));
    }
    auto body = stmt(node->body.get(), this);
    res->body.reset(body);
    res->line = node->line;
    return res;
}