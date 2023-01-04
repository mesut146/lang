#pragma once

#include "parser/Ast.h"
#include <stdexcept>

#define def \
    { return nullptr; }
#define todo(name) \
  { throw std::runtime_error(std::string("todo: ")+name); }

template<class R, class A>
class Visitor {
public:
    virtual R visitUnit(Unit *unit, A arg) todo("Unit");

    virtual R visitImportStmt(ImportStmt *, A arg) todo("Import")

    virtual R visitBaseDecl(BaseDecl *, A arg) todo("BaseDecl")

    virtual R visitTypeDecl(TypeDecl *, A arg) todo("TypeDecl")

    virtual R visitEnumDecl(EnumDecl *, A arg) todo("Enum")

    virtual R visitFieldDecl(FieldDecl *, A arg) todo("FieldDecl")

    virtual R visitMethod(Method *, A arg) todo("Param")

    virtual R visitParam(Param *, A arg) todo("Param")

    virtual R visitLiteral(Literal *lit, A arg) todo("Literal")

    virtual R visitSimpleName(SimpleName *sn, A arg) todo("SimpleName")

    virtual R visitQName(QName *qn, A arg) todo("QName")

    virtual R visitType(Type *type, A arg) todo("Type")


    virtual R visitVarDecl(VarDecl *, A arg) todo("VarDecl")

    virtual R visitVarDeclExpr(VarDeclExpr *, A arg) todo("VarDecl")

    virtual R visitFragment(Fragment *, A arg) todo("Fragment")

    virtual R visitRefExpr(RefExpr *e, A arg) todo("Ref")

            virtual R visitDerefExpr(DerefExpr *e, A arg) todo("deref")

            virtual R visitUnary(Unary *, A arg) todo("Unary")

    virtual R visitAssign(Assign *, A arg) todo("Assign")

    virtual R visitInfix(Infix *, A arg) todo("Infix")

    virtual R visitAsExpr(AsExpr *, A arg) todo("as")

    virtual R visitPostfix(Postfix *, A arg) todo("Postfix")

    virtual R visitTernary(Ternary *, A arg) todo("Ternary")

    virtual R visitMethodCall(MethodCall *, A arg) todo("MethodCall")

    virtual R visitFieldAccess(FieldAccess *, A arg) todo("FieldAccess")

    virtual R visitArrayAccess(ArrayAccess *, A arg) todo ("ArrayAccess")

    virtual R visitArrayExpr(ArrayExpr *, A arg) todo("ArrayExpr")

    virtual R visitArrayCreation(ArrayCreation *, A arg) todo("ArrayCreation")

    virtual R visitParExpr(ParExpr *, A arg) todo("ParExpr")

    virtual R visitObjExpr(ObjExpr *, A arg) todo("ObjExpr")

    virtual R visitAnonyObjExpr(MapExpr *, A arg) todo("MapExpr")

    //statements
    virtual R visitBlock(Block *, A arg) todo("Block")
    virtual R visitExprStmt(ExprStmt *, A arg) todo("ExprStmt")
    virtual R visitAssertStmt(AssertStmt *a, A arg) todo("assert")
    virtual R visitReturnStmt(ReturnStmt *, A arg) todo("Return")

    virtual R visitContinueStmt(ContinueStmt *, A arg) todo("Continue")

    virtual R visitBreakStmt(BreakStmt *, A arg) todo("BreakStmt")

    virtual R visitIfStmt(IfStmt *, A arg) todo("IfStmt")

    virtual R visitIfLetStmt(IfLetStmt *, A arg) todo("if let")

    virtual R visitWhileStmt(WhileStmt *, A arg) todo("WhileStmt")

    virtual R visitDoWhile(DoWhile *, A arg) todo("DoWhile")

    virtual R visitForStmt(ForStmt *, A arg) todo("ForStmt")

    virtual R visitForEach(ForEach *, A arg) todo("for each")
};
