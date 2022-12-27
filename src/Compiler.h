#pragma once

#include "BaseVisitor.h"
#include <fstream>
#include <string>
#include <llvm/IR/Value.h>

struct Compiler: public BaseVisitor<void*,void*>{
    std::string srcDir;
    std::string outDir;
    Unit *unit;

    void compileAll();

    void compile(const std::string &path);

    void* visitBlock(Block *b, void* arg) override;
    void* visitReturnStmt(ReturnStmt *t, void* arg) override;
    void* visitExprStmt(ExprStmt *b, void* arg) override;
    void* visitInfix(Infix *i, void* arg) override;
    void* visitSimpleName(SimpleName *n, void* arg) override;
    void* visitMethodCall(MethodCall *n, void* arg) override;
    void* visitLiteral(Literal *n, void* arg) override;
};