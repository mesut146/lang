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
    std::map<std::string, llvm::Function *> funcMap;
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

    std::any visitParExpr(ParExpr *node) override;
    llvm::Value *andOr(Expression *l, Expression *r, bool isand);
    std::any visitInfix(Infix *node) override;
    std::any visitUnary(Unary *node) override;
    std::any visitAssign(Assign *node) override;
    std::any visitSimpleName(SimpleName *node) override;
    std::any visitMethodCall(MethodCall *node) override;
    std::any visitLiteral(Literal *node) override;
    std::any visitObjExpr(ObjExpr *node) override;
    std::any visitType(Type *node) override;
    std::any visitFieldAccess(FieldAccess *node) override;
    std::any visitRefExpr(RefExpr *node) override;
    std::any visitDerefExpr(DerefExpr *n) override;
    std::any visitIsExpr(IsExpr *node) override;
    std::any visitAsExpr(AsExpr *node) override;
    std::any visitArrayAccess(ArrayAccess *node) override;
    std::any visitArrayExpr(ArrayExpr *node) override;
    void child(Expression *node, llvm::Value *ptr);
    std::any array(ArrayExpr *node, llvm::Value *ptr);
    void object(ObjExpr *node, llvm::Value *ptr, RType *tt);
    std::any slice(ArrayAccess *node, llvm::Value *ptr, Type *arrty);

    std::any visitBlock(Block *node) override;
    std::any visitVarDecl(VarDecl *node) override;
    std::any visitReturnStmt(ReturnStmt *node) override;
    std::any visitExprStmt(ExprStmt *node) override;
    std::any visitIfStmt(IfStmt *node) override;
    std::any visitIfLetStmt(IfLetStmt *node) override;
    std::any visitAssertStmt(AssertStmt *node) override;
    std::any visitWhileStmt(WhileStmt *node) override;
    std::any visitContinueStmt(ContinueStmt *node) override;
    std::any visitBreakStmt(BreakStmt *node) override;
};


struct CompilerHelper {
    Compiler *c;
};