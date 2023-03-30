#pragma once

#include "Visitor.h"
#include "parser/Ast.h"

class Resolver;

class IdGen : public Visitor {
public:
    Resolver *resolver;

    IdGen(Resolver *resolver) : resolver(resolver) {}
    std::any get(Expression *node);

    std::any visitInfix(Infix *node) override;
    std::any visitAssign(Assign *node) override;
    std::any visitMethodCall(MethodCall *node) override;
    std::any visitSimpleName(SimpleName *node) override;
    std::any visitLiteral(Literal *node) override;
    std::any visitRefExpr(RefExpr *node) override;
    std::any visitType(Type *node) override;
    std::any visitObjExpr(ObjExpr *node) override;
    std::any visitFieldAccess(FieldAccess *node) override;
    std::any visitDerefExpr(DerefExpr *node) override;
    std::any visitParExpr(ParExpr *node) override;
    std::any visitUnary(Unary *node) override;
    std::any visitArrayAccess(ArrayAccess *node) override;
    std::any visitArrayExpr(ArrayExpr *node) override;
    std::any visitAsExpr(AsExpr *node) override;
    std::any visitIsExpr(IsExpr *node) override;
};