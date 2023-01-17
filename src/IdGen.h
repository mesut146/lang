#pragma once

#include "Visitor.h"
#include "parser/Ast.h"

class Resolver;

class IdGen : public Visitor {
public:
    Unit *unit;
    Resolver *resolver;

    IdGen(Resolver *resolver) : resolver(resolver) {}


    void *visitInfix(Infix *node) override;
    void *visitMethodCall(MethodCall *node) override;
    void *visitSimpleName(SimpleName *node) override;
    void *visitLiteral(Literal *node) override;
    void *visitRefExpr(RefExpr *node) override;
    void *visitType(Type *node) override;
    void *visitObjExpr(ObjExpr *node) override;
    void *visitFieldAccess(FieldAccess *node) override;
    void *visitDerefExpr(DerefExpr *node) override;
    void *visitParExpr(ParExpr *node) override;
    void *visitUnary(Unary *node) override;
    void *visitArrayAccess(ArrayAccess *node) override;
    void *visitArrayExpr(ArrayExpr *node) override;
};