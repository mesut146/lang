#pragma once

#include "Visitor.h"

template<class R, class A>
class BaseVisitor : public Visitor<R, A> {
public:
    virtual R visitUnit(Unit *unit, A arg) {
        for (auto t : unit->types) {
            t->accept((Visitor<R, A> *) this, unit);
        }
        return nullptr;
    }

    virtual R visitImportStmt(ImportStmt *, A arg) { return nullptr; }

    virtual R visitBaseDecl(BaseDecl *, A arg) { return nullptr; }

    virtual R visitTypeDecl(TypeDecl *, A arg) { return nullptr; }

    virtual R visitEnumDecl(EnumDecl *, A arg) { return nullptr; }

    virtual R visitFieldDecl(FieldDecl *, A arg) { return nullptr; }

    virtual R visitMethod(Method *, A arg) { return nullptr; }

    virtual R visitBlock(Block *, A arg) { return nullptr; }

    virtual R visitExprStmt(ExprStmt *es, A arg) { return es->expr->accept(this, arg); }

    virtual R visitLiteral(Literal *lit, A arg) { return nullptr; }

    virtual R visitSimpleName(SimpleName *sn, A arg) { return nullptr; }

    virtual R visitQName(QName *qn, A arg) { return nullptr; }

    virtual R visitType(Type *type, A arg) { return nullptr; }

    virtual R visitVarDecl(VarDecl *, A arg) { return nullptr; }

    virtual R visitVarDeclExpr(VarDeclExpr *, A arg) { return nullptr; }

    virtual R visitFragment(Fragment *, A arg) { return nullptr; }

    virtual R visitUnary(Unary *, A arg) { return nullptr; }

    virtual R visitAssign(Assign *, A arg) { return nullptr; }

    virtual R visitInfix(Infix *infix, A arg) {
        infix->left->accept(this, infix);
        infix->right->accept(this, infix);
        return nullptr;
    }

    virtual R visitPostfix(Postfix *, A arg) { return nullptr; }

    virtual R visitTernary(Ternary *, A arg) { return nullptr; }

    virtual R visitMethodCall(MethodCall *, A arg) { return nullptr; }

    virtual R visitFieldAccess(FieldAccess *, A arg) { return nullptr; }

    virtual R visitArrayAccess(ArrayAccess *, A arg) { return nullptr; }

    virtual R visitArrayExpr(ArrayExpr *, A arg) { return nullptr; }

    virtual R visitArrayCreation(ArrayCreation *, A arg) { return nullptr; }

    virtual R visitParExpr(ParExpr *, A arg) { return nullptr; }

    virtual R visitObjExpr(ObjExpr *, A arg) { return nullptr; }

    virtual R visitAnonyObjExpr(MapExpr *, A arg) { return nullptr; }

    virtual R visitReturnStmt(ReturnStmt *, A arg) { return nullptr; }

    virtual R visitContinueStmt(ContinueStmt *, A arg) { return nullptr; }

    virtual R visitBreakStmt(BreakStmt *, A arg) { return nullptr; }

    virtual R visitIfStmt(IfStmt *, A arg) { return nullptr; }

    virtual R visitWhileStmt(WhileStmt *, A arg) { return nullptr; }

    virtual R visitDoWhile(DoWhile *, A arg) { return nullptr; }

    virtual R visitForStmt(ForStmt *, A arg) { return nullptr; }

    virtual R visitForEach(ForEach *, A arg) { return nullptr; }
};