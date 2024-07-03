#pragma once

#include "parser/Ast.h"
#include <any>
#include <stdexcept>

#define todo(name) \
    { throw std::runtime_error(std::string("todo: ") + name); }


class Visitor {
public:
    virtual std::any visitStructDecl(StructDecl *node) todo("TypeDecl");
    virtual std::any visitEnumDecl(EnumDecl *node) todo("Enum");
    virtual std::any visitTrait(Trait *node) todo("Trait");
    virtual std::any visitImpl(Impl *node) todo("Impl");
    virtual std::any visitExtern(Extern *node) todo("Extern");
    virtual std::any visitFieldDecl(FieldDecl *node) todo("FieldDecl");
    virtual std::any visitMethod(Method *node) todo("Param");
    virtual std::any visitParam(Param *node) todo("Param");

    virtual std::any visitLiteral(Literal *node) todo("Literal");
    virtual std::any visitSimpleName(SimpleName *node) todo("SimpleName");
    virtual std::any visitType(Type *node) todo("Type");
    virtual std::any visitFragment(Fragment *node) todo("Fragment");
    virtual std::any visitRefExpr(RefExpr *node) todo("Ref");
    virtual std::any visitDerefExpr(DerefExpr *node) todo("deref");
    virtual std::any visitUnary(Unary *node) todo("Unary");
    virtual std::any visitAssign(Assign *node) todo("Assign");
    virtual std::any visitInfix(Infix *node) todo("Infix");
    virtual std::any visitAsExpr(AsExpr *node) todo("AsExpr");
    virtual std::any visitIsExpr(IsExpr *node) todo("IsExpr");
    virtual std::any visitMethodCall(MethodCall *node) todo("MethodCall");
    virtual std::any visitFieldAccess(FieldAccess *node) todo("FieldAccess");
    virtual std::any visitArrayAccess(ArrayAccess *node) todo("ArrayAccess");
    virtual std::any visitArrayExpr(ArrayExpr *node) todo("ArrayExpr");
    virtual std::any visitParExpr(ParExpr *node) todo("ParExpr");
    virtual std::any visitObjExpr(ObjExpr *node) todo("ObjExpr");

    //statements
    virtual std::any visitVarDecl(VarDecl *node) todo("VarDecl");
    virtual std::any visitVarDeclExpr(VarDeclExpr *node) todo("VarDeclExpr");
    virtual std::any visitBlock(Block *node) todo("Block");
    virtual std::any visitExprStmt(ExprStmt *node) todo("ExprStmt");
    virtual std::any visitReturnStmt(ReturnStmt *node) todo("Return");
    virtual std::any visitContinueStmt(ContinueStmt *node) todo("Continue");
    virtual std::any visitBreakStmt(BreakStmt *node) todo("BreakStmt");
    virtual std::any visitIfStmt(IfStmt *node) todo("IfStmt");
    virtual std::any visitIfLetStmt(IfLetStmt *node) todo("if let");
    virtual std::any visitWhileStmt(WhileStmt *node) todo("WhileStmt");
    virtual std::any visitForStmt(ForStmt *node) todo("ForStmt");
};
