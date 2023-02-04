#pragma once

#include "Visitor.h"

class AstCopier : public Visitor {
public:
    std::any visitLiteral(Literal *node) override;
    std::any visitSimpleName(SimpleName *node) override;
    std::any visitType(Type *node) override;
    std::any visitInfix(Infix *node) override;
    std::any visitAssign(Assign *node) override;
    std::any visitArrayAccess(ArrayAccess *node) override;
    std::any visitFieldAccess(FieldAccess *node) override;
    std::any visitUnary(Unary *node) override;
    std::any visitFragment(Fragment *node) override;
    std::any visitObjExpr(ObjExpr *node) override;
    std::any visitMethodCall(MethodCall *node) override;
    std::any visitDerefExpr(DerefExpr *node) override;

    std::any visitVarDecl(VarDecl *node) override;
    std::any visitVarDeclExpr(VarDeclExpr *node) override;
    std::any visitBlock(Block *node) override;
    std::any visitReturnStmt(ReturnStmt *node) override;
    std::any visitExprStmt(ExprStmt *node) override;
    std::any visitWhileStmt(WhileStmt *node) override;
    std::any visitIfStmt(IfStmt *node) override;
    std::any visitIfLetStmt(IfLetStmt *node) override;
    std::any visitMethod(Method *node) override;
};