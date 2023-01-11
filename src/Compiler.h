#pragma once

#include "Resolver.h"
#include "Visitor.h"
#include <fstream>
#include <llvm/IR/Value.h>
#include <string>


struct Compiler : public Visitor {
    std::string srcDir;
    std::string outDir;
    std::shared_ptr<Unit> unit;
    llvm::Function *func = nullptr;
    Method *curMethod = nullptr;
    std::shared_ptr<Resolver> resolv;
    std::vector<llvm::BasicBlock *> loops;
    std::vector<llvm::BasicBlock *> loopNext;

    void compileAll();
    void compile(const std::string &path);
    void createProtos();
    void genCode(Method *m);

    llvm::Value *gen(Expression *e);
    llvm::Value *loadPtr(Expression *e);
    llvm::Value *cast(Expression *expr, Type *type);
    llvm::Type *mapType(Type *t);
    void make_proto(Method *m);
    void makeDecl(BaseDecl *bd);
    void initParams(Method *m);
    void makeLocals(Statement *st);

    void *visitBlock(Block *b) override;
    void *visitReturnStmt(ReturnStmt *t) override;
    void *visitExprStmt(ExprStmt *b) override;
    void *visitIfStmt(IfStmt *b) override;
    void *visitIfLetStmt(IfLetStmt *b) override;

    void *visitParExpr(ParExpr *i) override;
    llvm::Value *andOr(Expression *l, Expression *r, bool isand);
    void *visitInfix(Infix *i) override;
    void *visitUnary(Unary *u) override;
    void *visitAssign(Assign *i) override;
    void *visitSimpleName(SimpleName *n) override;
    void *visitMethodCall(MethodCall *n) override;
    void *visitLiteral(Literal *n) override;
    void *visitAssertStmt(AssertStmt *n) override;
    void *visitVarDecl(VarDecl *n) override;
    void *visitObjExpr(ObjExpr *n) override;
    void *visitType(Type *n) override;
    void *visitFieldAccess(FieldAccess *n) override;
    void *visitRefExpr(RefExpr *n) override;
    void *visitDerefExpr(DerefExpr *n) override;

    void *visitIsExpr(IsExpr *ie) override;
    void *visitAsExpr(AsExpr *e) override;
    void *visitArrayAccess(ArrayAccess *node) override;
    void *visitWhileStmt(WhileStmt *node) override;
    void *visitContinueStmt(ContinueStmt *node) override;
    void *visitBreakStmt(BreakStmt *node) override;
};