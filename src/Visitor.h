#pragma once

#include "parser/Ast.h"
#include <stdexcept>

#define todo(name) \
    { throw std::runtime_error(std::string("todo: ") + name); }


class Visitor {
public:
    virtual void *visitUnit(Unit *node) todo("Unit");
    virtual void *visitImportStmt(ImportStmt *node) todo("Import");
    virtual void *visitBaseDecl(BaseDecl *node) todo("BaseDecl");
    virtual void *visitTypeDecl(TypeDecl *node) todo("TypeDecl");
    virtual void *visitEnumDecl(EnumDecl *node) todo("Enum");
    virtual void *visitTrait(Trait *node) todo("Trait");
    virtual void *visitImpl(Impl *node) todo("Impl");
    virtual void *visitFieldDecl(FieldDecl *node) todo("FieldDecl");
    virtual void *visitMethod(Method *node) todo("Param");
    virtual void *visitParam(Param *node) todo("Param");

    virtual void *visitLiteral(Literal *node) todo("Literal");
    virtual void *visitSimpleName(SimpleName *node) todo("SimpleName");
    virtual void *visitQName(QName *node) todo("QName");
    virtual void *visitType(Type *node) todo("Type");
    virtual void *visitVarDecl(VarDecl *node) todo("VarDecl");
    virtual void *visitVarDeclExpr(VarDeclExpr *node) todo("VarDeclExpr");
    virtual void *visitFragment(Fragment *node) todo("Fragment");
    virtual void *visitRefExpr(RefExpr *node) todo("Ref");
    virtual void *visitDerefExpr(DerefExpr *node) todo("deref");
    virtual void *visitUnary(Unary *node) todo("Unary");
    virtual void *visitAssign(Assign *node) todo("Assign");
    virtual void *visitInfix(Infix *node) todo("Infix");
    virtual void *visitAsExpr(AsExpr *node) todo("AsExpr");
    virtual void *visitIsExpr(IsExpr *node) todo("IsExpr");
    virtual void *visitPostfix(Postfix *node) todo("Postfix");
    virtual void *visitTernary(Ternary *node) todo("Ternary");
    virtual void *visitMethodCall(MethodCall *node) todo("MethodCall");
    virtual void *visitFieldAccess(FieldAccess *node) todo("FieldAccess");
    virtual void *visitArrayAccess(ArrayAccess *node) todo("ArrayAccess");
    virtual void *visitArrayExpr(ArrayExpr *node) todo("ArrayExpr");
    virtual void *visitArrayCreation(ArrayCreation *node) todo("ArrayCreation");
    virtual void *visitParExpr(ParExpr *node) todo("ParExpr");
    virtual void *visitObjExpr(ObjExpr *node) todo("ObjExpr");
    virtual void *visitUnsafe(UnsafeBlock *node) todo("Unsafe");

    //statements
    virtual void *visitBlock(Block *node) todo("Block");
    virtual void *visitExprStmt(ExprStmt *node) todo("ExprStmt");
    virtual void *visitAssertStmt(AssertStmt *node) todo("assert");
    virtual void *visitReturnStmt(ReturnStmt *node) todo("Return");
    virtual void *visitContinueStmt(ContinueStmt *node) todo("Continue");
    virtual void *visitBreakStmt(BreakStmt *node) todo("BreakStmt");
    virtual void *visitIfStmt(IfStmt *node) todo("IfStmt");
    virtual void *visitIfLetStmt(IfLetStmt *node) todo("if let");
    virtual void *visitWhileStmt(WhileStmt *node) todo("WhileStmt");
    virtual void *visitDoWhile(DoWhile *node) todo("DoWhile");
    virtual void *visitForStmt(ForStmt *node) todo("ForStmt");
};
