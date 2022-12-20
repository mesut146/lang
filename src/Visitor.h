#pragma once

#include "parser/Ast.h"

template<class R, class A>
class Visitor {
public:
    virtual R visitUnit(Unit *unit, A arg) = 0;

    virtual R visitImportStmt(ImportStmt *, A arg) = 0;

    virtual R visitBaseDecl(BaseDecl *, A arg) = 0;

    virtual R visitTypeDecl(TypeDecl *, A arg) = 0;

    virtual R visitEnumDecl(EnumDecl *, A arg) = 0;

    virtual R visitFieldDecl(FieldDecl *, A arg) = 0;

    virtual R visitMethod(Method *, A arg) = 0;

    virtual R visitParam(Param *, A arg) = 0;

    virtual R visitBlock(Block *, A arg) = 0;

    virtual R visitExprStmt(ExprStmt *, A arg) = 0;

    virtual R visitLiteral(Literal *lit, A arg) = 0;

    virtual R visitSimpleName(SimpleName *sn, A arg) = 0;

    virtual R visitQName(QName *qn, A arg) = 0;

    virtual R visitType(Type *type, A arg) = 0;


    virtual R visitVarDecl(VarDecl *, A arg) = 0;

    virtual R visitVarDeclExpr(VarDeclExpr *, A arg) = 0;

    virtual R visitFragment(Fragment *, A arg) = 0;

    virtual R visitRefExpr(RefExpr *e, A arg) = 0;

    virtual R visitDerefExpr(DerefExpr *e, A arg) = 0;

    virtual R visitUnary(Unary *, A arg) = 0;

    virtual R visitAssign(Assign *, A arg) = 0;

    virtual R visitInfix(Infix *, A arg) = 0;

    virtual R visitAsExpr(AsExpr *, A arg) = 0;

    virtual R visitPostfix(Postfix *, A arg) = 0;

    virtual R visitTernary(Ternary *, A arg) = 0;

    virtual R visitMethodCall(MethodCall *, A arg) = 0;

    virtual R visitFieldAccess(FieldAccess *, A arg) = 0;

    virtual R visitArrayAccess(ArrayAccess *, A arg) = 0;

    virtual R visitArrayExpr(ArrayExpr *, A arg) = 0;

    virtual R visitArrayCreation(ArrayCreation *, A arg) = 0;

    virtual R visitParExpr(ParExpr *, A arg) = 0;

    virtual R visitObjExpr(ObjExpr *, A arg) = 0;

    virtual R visitAnonyObjExpr(MapExpr *, A arg) = 0;

    //statements

    virtual R visitReturnStmt(ReturnStmt *, A arg) = 0;

    virtual R visitContinueStmt(ContinueStmt *, A arg) = 0;

    virtual R visitBreakStmt(BreakStmt *, A arg) = 0;

    virtual R visitIfStmt(IfStmt *, A arg) = 0;

    virtual R visitWhileStmt(WhileStmt *, A arg) = 0;

    virtual R visitDoWhile(DoWhile *, A arg) = 0;

    virtual R visitForStmt(ForStmt *, A arg) = 0;

    virtual R visitForEach(ForEach *, A arg) = 0;

};
