#pragma once

#include "Visitor.h"

class Transformer : public Visitor {
public:
    Unit *unit;

  
    //void *visitMethod(Method *m, void *arg) override;
     R visitLiteral(Literal *lit, A arg) override;

     R visitSimpleName(SimpleName *sn, A arg) override;

     //R visitQName(QName *qn, A arg) override;

     R visitType(Type *type, A arg) override;
/*
     R visitVarDecl(VarDecl *, A arg) override;

     R visitVarDeclExpr(VarDeclExpr *, A arg) override;

     R visitFragment(Fragment *, A arg) override;

     R visitRefExpr(RefExpr *e, A arg) override;

     R visitDerefExpr(DerefExpr *e, A arg) override;

     R visitUnary(Unary *, A arg) override;

     R visitAssign(Assign *, A arg) override;*/
     R visitInfix(Infix *, A arg) override;
/*
     R visitAsExpr(AsExpr *, A arg) override;
     R visitIsExpr(IsExpr *, A arg) override;

     R visitPostfix(Postfix *, A arg) override;

     R visitTernary(Ternary *, A arg) override;

     R visitMethodCall(MethodCall *, A arg) override;

     R visitFieldAccess(FieldAccess *, A arg) override;

     R visitArrayAccess(ArrayAccess *, A arg) override;

     R visitArrayExpr(ArrayExpr *, A arg) override;

     R visitArrayCreation(ArrayCreation *, A arg) override;

     R visitParExpr(ParExpr *, A arg) override;

     R visitObjExpr(ObjExpr *, A arg) override;

     R visitAnonyObjExpr(MapExpr *, A arg) override;
*/
    //statements
     R visitBlock(Block *, A arg) override;
     /*
     R visitExprStmt(ExprStmt *, A arg) override;
     R visitAssertStmt(AssertStmt *a, A arg) override;*/
     R visitReturnStmt(ReturnStmt *, A arg) override;
     /*R visitContinueStmt(ContinueStmt *, A arg) override;
     R visitBreakStmt(BreakStmt *, A arg) override;
     R visitIfStmt(IfStmt *, A arg) override;
     R visitIfLetStmt(IfLetStmt *, A arg) override;
     R visitWhileStmt(WhileStmt *, A arg) override;
     R visitDoWhile(DoWhile *, A arg) override;
     R visitForStmt(ForStmt *, A arg) override;
     R visitForEach(ForEach *, A arg) override;*/
};