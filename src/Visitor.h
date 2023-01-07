#pragma once

#include "parser/Ast.h"
#include <stdexcept>

#define todo(name) \
    { throw std::runtime_error(std::string("todo: ") + name); }


class Visitor {
public:
    virtual void *visitUnit(Unit *node, void *arg) todo("Unit");
    virtual void *visitImportStmt(ImportStmt *node, void *arg) todo("Import");
    virtual void *visitBaseDecl(BaseDecl *node, void *arg) todo("BaseDecl");
    virtual void *visitTypeDecl(TypeDecl *node, void *arg) todo("TypeDecl");
    virtual void *visitEnumDecl(EnumDecl *node, void *arg) todo("Enum");
    virtual void *visitFieldDecl(FieldDecl *node, void *arg) todo("FieldDecl");
    virtual void *visitMethod(Method *node, void *arg) todo("Param");
    virtual void *visitParam(Param *node, void *arg) todo("Param");

    virtual void *visitLiteral(Literal *node, void *arg) todo("Literal");
    virtual void *visitSimpleName(SimpleName *node, void *arg) todo("SimpleName");
    virtual void *visitQName(QName *node, void *arg) todo("QName");
    virtual void *visitType(Type *node, void *arg) todo("Type");
    virtual void *visitVarDecl(VarDecl *node, void *arg) todo("VarDecl");
    virtual void *visitVarDeclExpr(VarDeclExpr *node, void *arg) todo("VarDeclExpr");
    virtual void *visitFragment(Fragment *node, void *arg) todo("Fragment");
    virtual void *visitRefExpr(RefExpr *e, void *arg) todo("Ref");
    virtual void *visitDerefExpr(DerefExpr *e, void *arg) todo("deref");
    virtual void *visitUnary(Unary *node, void *arg) todo("Unary");
    virtual void *visitAssign(Assign *, void *arg) todo("Assign");
    virtual void *visitInfix(Infix *node, void *arg) todo("Infix");
    virtual void *visitAsExpr(AsExpr *node, void *arg) todo("AsExpr");
    virtual void *visitIsExpr(IsExpr *node, void *arg) todo("IsExpr");
    virtual void *visitPostfix(Postfix *node, void *arg) todo("Postfix");
    virtual void *visitTernary(Ternary *node, void *arg) todo("Ternary");
    virtual void *visitMethodCall(MethodCall *node, void *arg) todo("MethodCall");
    virtual void *visitFieldAccess(FieldAccess *node, void *arg) todo("FieldAccess");
    virtual void *visitArrayAccess(ArrayAccess *node, void *arg) todo("ArrayAccess");
    virtual void *visitArrayExpr(ArrayExpr *node, void *arg) todo("ArrayExpr");
    virtual void *visitArrayCreation(ArrayCreation *node, void *arg) todo("ArrayCreation");
    virtual void *visitParExpr(ParExpr *node, void *arg) todo("ParExpr");
    virtual void *visitObjExpr(ObjExpr *node, void *arg) todo("ObjExpr");
    virtual void *visitAnonyObjExpr(MapExpr *node, void *arg) todo("MapExpr");

    //statements
    virtual void *visitBlock(Block *node, void *arg) todo("Block");
    virtual void *visitExprStmt(ExprStmt *node, void *arg) todo("ExprStmt");
    virtual void *visitAssertStmt(AssertStmt *node, void *arg) todo("assert");
    virtual void *visitReturnStmt(ReturnStmt *node, void *arg) todo("Return");
    virtual void *visitContinueStmt(ContinueStmt *node, void *arg) todo("Continue");
    virtual void *visitBreakStmt(BreakStmt *node, void *arg) todo("BreakStmt");
    virtual void *visitIfStmt(IfStmt *node, void *arg) todo("IfStmt");
    virtual void *visitIfLetStmt(IfLetStmt *node, void *arg) todo("if let");
    virtual void *visitWhileStmt(WhileStmt *node, void *arg) todo("WhileStmt");
    virtual void *visitDoWhile(DoWhile *node, void *arg) todo("DoWhile");
    virtual void *visitForStmt(ForStmt *node, void *arg) todo("ForStmt");
    virtual void *visitForEach(ForEach *node, void *arg) todo("for each");
};
