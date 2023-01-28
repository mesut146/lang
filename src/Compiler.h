#pragma once

#include <fstream>
#include <string>

#include "Resolver.h"
#include "Visitor.h"
#include <llvm/IR/Value.h>
#include <llvm/Target/TargetMachine.h>


struct Compiler : public Visitor {
    std::string srcDir;
    std::string outDir;
    std::shared_ptr<Unit> unit;
    llvm::Function *func = nullptr;
    Method *curMethod = nullptr;
    std::shared_ptr<Resolver> resolv;
    std::vector<llvm::BasicBlock *> loops;
    std::vector<llvm::BasicBlock *> loopNext;
    llvm::Value *retPtr = nullptr;
    std::string TargetTriple;
    llvm::TargetMachine *TargetMachine;
    int allocIdx = 0;

    void init();
    void emit(std::string &Filename);
    void compileAll();
    std::optional<std::string> compile(const std::string &path);
    void createProtos();
    void genCode(std::unique_ptr<Method> &m);
    void genCode(Method *m);

    int getSize(Type *type);
    int getSize(BaseDecl *decl);
    int getOffset(EnumVariant *variant, int index);
    void setField(Expression *expr, Type *type, bool do_cast, llvm::Value *entPtr);
    llvm::Value *gen(Expression *e);
    llvm::Value *gen(std::unique_ptr<Expression> &e);
    llvm::Value *loadPtr(Expression *e);
    llvm::Value *loadPtr(std::unique_ptr<Expression> &e);
    llvm::Value *cast(Expression *expr, Type *type);
    llvm::Type *mapType(Type *t);
    void make_proto(std::unique_ptr<Method> &m);
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
    void *visitArrayExpr(ArrayExpr *node) override;
    void *array(ArrayExpr *node, llvm::Value *ptr);
    void child(Expression *e, llvm::Value *ptr);
    void object(ObjExpr *e, llvm::Value *ptr, RType *tt);
};