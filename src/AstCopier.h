#pragma once

#include "Visitor.h"

class AstCopier : public Visitor {
public:
    void *visitLiteral(Literal *node) override;
    void *visitSimpleName(SimpleName *node) override;
    void *visitType(Type *node) override;
    void *visitInfix(Infix *node) override;
    void *visitAssign(Assign *node) override;
    void *visitArrayAccess(ArrayAccess *node) override;
    void *visitFieldAccess(FieldAccess *node) override;
    void *visitUnary(Unary *node) override;

    void *visitBlock(Block *node) override;
    void *visitReturnStmt(ReturnStmt *node) override;
    void *visitVarDecl(VarDecl *node) override;
    void *visitVarDeclExpr(VarDeclExpr *node) override;
    void *visitFragment(Fragment *node) override;
    void *visitObjExpr(ObjExpr *node) override;
    void *visitMethodCall(MethodCall *node) override;
    void *visitExprStmt(ExprStmt *node) override;
    void *visitWhileStmt(WhileStmt *node) override;
    void *visitIfStmt(IfStmt *node) override;
    void *visitIfLetStmt(IfLetStmt *node) override;
    void *visitMethod(Method *node) override;
};