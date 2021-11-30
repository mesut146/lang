#pragma once

#include "parser/Ast.h"

class Visitor {

    virtual void visitBlock(Block *) = 0;

    virtual void visitImportStmt(ImportStmt *) = 0;

    virtual void visitMethod(Method *) = 0;

    virtual void visitExprStmt(ExprStmt *) = 0;

    virtual void visitImportStmt(ImportStmt *) = 0;

    virtual void visitImportStmt(ImportStmt *) = 0;

    virtual void visitVarDecl(VarDecl *) = 0;

    virtual void visitVarDeclExpr(VarDeclExpr *) = 0;

    virtual void visitUnary(Unary *) = 0;

    virtual void visitAssign(Assign *) = 0;

    virtual void visitInfix(Infix *) = 0;

    virtual void visitPostfix(Postfix *) = 0;

    virtual void visitTernary(Ternary *) = 0;

    virtual void visitMethodCall(MethodCall *) = 0;

    virtual void visitFieldAccess(FieldAccess *) = 0;

    virtual void visitArrayAccess(ArrayAccess *) = 0;

    virtual void visitArrayExpr(ArrayExpr *) = 0;

    virtual void visitParExpr(ParExpr *) = 0;

    virtual void visitObjExpr(ObjExpr *) = 0;

    virtual void visitAnonyObjExpr(AnonyObjExpr *) = 0;

    virtual void visitReturnStmt(ReturnStmt *) = 0;

    virtual void visitContinueStmt(ContinueStmt *) = 0;

    virtual void visitBreakStmt(BreakStmt *) = 0;

    virtual void visitIfStmt(IfStmt *) = 0;

    virtual void visitWhileStmt(WhileStmt *) = 0;

    virtual void visitDoWhile(DoWhile *) = 0;

    virtual void visitForStmt(ForStmt *) = 0;

    virtual void visitForEach(ForEach *) = 0;

    /*virtual void visitImportStmt(ImportStmt *) = 0;

    virtual void visitImportStmt(ImportStmt *) = 0;

    virtual void visitImportStmt(ImportStmt *) = 0;*/
};
