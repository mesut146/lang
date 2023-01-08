#pragma once

#include "Visitor.h"
#include "parser/Ast.h"

class Resolver;

class IdGen : public Visitor {
public:
    Unit *unit;
    Resolver *resolver;

    IdGen(Resolver *resolver) : resolver(resolver) {}


    void *visitInfix(Infix *node, void *arg) override;
    void *visitMethodCall(MethodCall *node, void *arg) override;
    void *visitSimpleName(SimpleName *node, void *arg) override;
    void *visitLiteral(Literal *node, void *arg) override;
    void *visitRefExpr(RefExpr *node, void *arg) override;
    void *visitType(Type *node, void *arg) override;
    void *visitObjExpr(ObjExpr *node, void *arg) override;
    void *visitFieldAccess(FieldAccess *node, void *arg) override;
    void *visitDerefExpr(DerefExpr *node, void *arg) override;
    void *visitParExpr(ParExpr *node, void *arg) override;
    void *visitUnary(Unary *node, void *arg) override;
    void *visitArrayAccess(ArrayAccess *node, void *arg) override;
};