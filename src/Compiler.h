#pragma once

#include "BaseVisitor.h"
#include <fstream>
#include <string>
#include <llvm/IR/Value.h>
#include "Resolver.h"

struct Compiler: public BaseVisitor<void*,void*>{
    std::string srcDir;
    std::string outDir;
    Unit *unit;
    llvm::Function* func;
    Method* curMethod;
    Resolver* resolv;
    llvm::Type* expect;

    void compileAll();
    void compile(const std::string &path);
    
    llvm::Value *loadPtr( Expression *e) ;

    void* visitBlock(Block *b, void* arg) override;
    void* visitReturnStmt(ReturnStmt *t, void* arg) override;
    void* visitExprStmt(ExprStmt *b, void* arg) override;
    void* visitIfStmt(IfStmt *b, void* arg) override;
    void* visitIfLetStmt(IfLetStmt *b, void* arg) override;
    
    void* visitParExpr(ParExpr *i, void* arg) override;
    llvm::Value* andOr(llvm::Value* l, llvm::Value* r, bool isand);
    void* visitInfix(Infix *i, void* arg) override;
    void* visitAssign(Assign *i, void* arg) override;
    void* visitSimpleName(SimpleName *n, void* arg) override;
    void* visitMethodCall(MethodCall *n, void* arg) override;
    void* visitLiteral(Literal *n, void* arg) override;
    void* visitAssertStmt(AssertStmt *n, void* arg) override;
    void* visitVarDecl(VarDecl *n, void* arg) override;
    void* visitObjExpr(ObjExpr *n, void* arg) override;
    void* visitType(Type *n, void* arg) override;
    void* visitFieldAccess(FieldAccess *n, void* arg) override;
    void* visitRefExpr(RefExpr *n, void* arg) override;
    void* visitDerefExpr(DerefExpr *n, void* arg) override;
};