#pragma once

#include <fstream>
#include <string>

#include "Resolver.h"
#include "Visitor.h"
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Value.h>
#include <llvm/Target/TargetMachine.h>


bool doesAlloc(Expression *e);
bool isStrLit(Expression *e);

struct Compiler : public Visitor {
public:
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
    llvm::TargetMachine *TargetMachine = nullptr;
    llvm::IRBuilder<> *Builder = nullptr;
    llvm::LLVMContext *ctx = nullptr;
    llvm::Module *mod = nullptr;
    std::vector<llvm::Value *> allocArr;
    int allocIdx = 0;
    std::map<std::string, llvm::Value *> NamedValues;
    std::map<std::string, llvm::Type *> classMap;
    llvm::Function *printf_proto = nullptr;
    llvm::Function *exit_proto = nullptr;
    llvm::Function *mallocf = nullptr;
    llvm::StructType *sliceType = nullptr;
    llvm::StructType *stringType = nullptr;

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
    llvm::Value *branch(llvm::Value *val);
    llvm::ConstantInt *makeInt(int val);
    llvm::ConstantInt *makeInt(int val, int bits);
    llvm::Type *getInt(int bit);
    void setOrdinal(int index, llvm::Value *ptr);
    void simpleVariant(Type *n, llvm::Value *ptr);

    llvm::Function *make_printf();
    llvm::Function *make_exit();
    llvm::Function *make_malloc();
    llvm::StructType *make_slice_type();
    llvm::StructType *make_string_type();

    llvm::Value *load(llvm::Value *val);
    llvm::Value *loadPtr(Expression *e);
    llvm::Value *loadPtr(std::unique_ptr<Expression> &e);
    llvm::Value *cast(Expression *expr, Type *type);
    llvm::Type *mapType(Type *t);
    void make_proto(std::unique_ptr<Method> &m);
    void make_proto(Method *m);
    void makeDecl(BaseDecl *bd);
    void initParams(Method *m);
    void makeLocals(Statement *st);

    llvm::Value *gen(Expression *e);
    llvm::Value *gen(std::unique_ptr<Expression> &e);
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
    void child(Expression *e, llvm::Value *ptr);
    void *array(ArrayExpr *node, llvm::Value *ptr);
    void object(ObjExpr *e, llvm::Value *ptr, RType *tt);
    void *slice(ArrayAccess *node, llvm::Value *ptr, Type *arrty);
};


struct CompilerHelper {
    Compiler *c;
};