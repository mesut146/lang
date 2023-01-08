#pragma once

#include "Visitor.h"

class Transformer : public Visitor {
public:

    void *visitLiteral(Literal *lit, void *arg) override;
    void *visitSimpleName(SimpleName *sn, void *arg) override;
    void *visitType(Type *type, void *arg) override;
    void *visitInfix(Infix *i, void *arg) override;

    void *visitBlock(Block *, void *arg) override;
    void *visitReturnStmt(ReturnStmt *, void *arg) override;
    void *visitVarDecl(VarDecl *node, void *arg) override;
    void *visitVarDeclExpr(VarDeclExpr *node, void *arg) override;
    void *visitFragment(Fragment *node, void *arg) override;
    void *visitObjExpr(ObjExpr *node, void *arg) override;
    void *visitMethodCall(MethodCall *node, void *arg) override;
};