#pragma once

#include "Visitor.h"

class AstCopier : public Visitor {
public:
    void *visitLiteral(Literal *node, void *arg) override;
    void *visitSimpleName(SimpleName *node, void *arg) override;
    void *visitType(Type *node, void *arg) override;
    void *visitInfix(Infix *node, void *arg) override;

    void *visitBlock(Block *node, void *arg) override;
    void *visitReturnStmt(ReturnStmt *node, void *arg) override;
    void *visitVarDecl(VarDecl *node, void *arg) override;
    void *visitVarDeclExpr(VarDeclExpr *node, void *arg) override;
    void *visitFragment(Fragment *node, void *arg) override;
    void *visitObjExpr(ObjExpr *node, void *arg) override;
    void *visitMethodCall(MethodCall *node, void *arg) override;
};