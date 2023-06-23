#pragma once

#include <fstream>
#include <string>
#include <utility>

#include "Resolver.h"
#include "Visitor.h"
#include <llvm/IR/DIBuilder.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Value.h>
#include <llvm/Target/TargetMachine.h>


bool isStrLit(Expression *e);

std::vector<Method *> getMethods(Unit *unit);
void sort(std::vector<BaseDecl *> &list);

constexpr int ENUM_INDEX_SIZE = 32;
constexpr int ENUM_TAG_INDEX = 0;
constexpr int ENUM_DATA_INDEX = 1;
constexpr int SLICE_LEN_BITS = 32;

struct DebugInfo {
    llvm::DICompileUnit *cu;
    llvm::DIType *type;
    llvm::DIFile *file;
    llvm::DIScope *sp = nullptr;
    std::unordered_map<std::string, llvm::DIType *> types;
};

struct Compiler : public Visitor {
public:
    std::string srcDir;
    std::string outDir;
    std::vector<std::string> compiled;
    std::shared_ptr<Unit> unit;
    bool debug = true;
    llvm::Function *func = nullptr;
    Method *curMethod = nullptr;
    std::shared_ptr<Resolver> resolv;
    std::vector<llvm::BasicBlock *> loops;
    std::vector<llvm::BasicBlock *> loopNext;
    llvm::Value *retPtr = nullptr;
    std::string TargetTriple;
    llvm::TargetMachine *TargetMachine = nullptr;
    std::unique_ptr<llvm::IRBuilder<>> Builder;
    std::unique_ptr<llvm::DIBuilder> DBuilder;
    DebugInfo di;
    std::unique_ptr<llvm::LLVMContext> ctxp;
    std::unique_ptr<llvm::Module> mod;
    std::map<std::string, std::vector<llvm::Value *>> allocMap;
    std::map<std::string, llvm::Value *> NamedValues;
    std::map<std::string, llvm::Value *> varAlloc;
    std::map<std::string, llvm::Type *> classMap;
    std::map<std::string, llvm::Function *> funcMap;
    llvm::Function *printf_proto = nullptr;
    llvm::Function *exit_proto = nullptr;
    llvm::Function *mallocf = nullptr;
    llvm::StructType *sliceType = nullptr;
    llvm::StructType *stringType = nullptr;
    std::vector<Method *> virtuals;
    std::map<std::string, llvm::Constant *> vtables;
    std::map<Method *, int> virtualIndex;

    void init();
    void emit(std::string &Filename);
    void compileAll();
    std::optional<std::string> compile(const std::string &path);
    void link_run();
    void createProtos();
    void genCode(std::unique_ptr<Method> &m);
    void genCode(Method *m);
    void cleanup();
    void make_vtables();
    llvm::LLVMContext &ctx() { return *ctxp; };

    int getSize(const Type *type);
    int getSize(const Type &type) { return getSize(&type); }
    int getSize2(const Type *type);
    int getSize2(const Type &type) { return getSize2(&type); }
    void copy(llvm::Value *trg, llvm::Value *src, const Type &type);
    int getSize(BaseDecl *decl);
    int getSize2(BaseDecl *decl);
    int getOffset(EnumVariant *variant, int index);
    void setField(Expression *expr, const Type &type, bool do_cast, llvm::Value *entPtr);
    llvm::Value *branch(llvm::Value *val);
    llvm::ConstantInt *makeInt(int val);
    llvm::ConstantInt *makeInt(int val, int bits);
    llvm::Type *getInt(int bit);
    void setOrdinal(int index, llvm::Value *ptr);
    void simpleVariant(const Type &n, llvm::Value *ptr);
    llvm::Value *getTag(Expression *expr);
    bool doesAlloc(Expression *e);

    bool isRvo(Method *m) {
        return !m->type.isVoid() && isStruct(m->type);
    }

    bool isRvo(Expression *e) {
        auto m = resolv->resolve(e).targetMethod;
        return m && isRvo(m);
    }

    std::vector<llvm::Value *> makeIdx(int i1, int i2) {
        return {makeInt(i1, 64), makeInt(i2, 64)};
    }
    std::vector<llvm::Value *> makeIdx(int i1) {
        return {makeInt(i1, 64)};
    }
    llvm::Value *gep(llvm::Value *ptr, int i1, int i2) {
        auto idx = makeIdx(i1, i2);
        return Builder->CreateGEP(ptr->getType()->getPointerElementType(), ptr, idx);
    }
    llvm::Value *gep(llvm::Value *ptr, int i1) {
        auto idx = makeIdx(i1);
        return Builder->CreateGEP(ptr->getType()->getPointerElementType(), ptr, idx);
    }
    llvm::Value *gep(llvm::Value *ptr, llvm::Value *i1) {
        std::vector<llvm::Value *> idx = {i1};
        return Builder->CreateGEP(ptr->getType()->getPointerElementType(), ptr, idx);
    }
    llvm::Value *gep(llvm::Value *ptr, int i1, Expression *i2) {
        std::vector<llvm::Value *> idx = {makeInt(i1), cast(i2, Type("i64"))};
        return Builder->CreateGEP(ptr->getType()->getPointerElementType(), ptr, idx);
    }
    llvm::Value *gep(llvm::Value *ptr, Expression *i2) {
        std::vector<llvm::Value *> idx = {cast(i2, Type("i64"))};
        return Builder->CreateGEP(ptr->getType()->getPointerElementType(), ptr, idx);
    }
    llvm::Value *gep2(llvm::Value *ptr, int idx) {
        return Builder->CreateStructGEP(ptr->getType()->getPointerElementType(), ptr, idx);
    }
    llvm::Value *getAlloc(Expression *e) {
        auto &arr = allocMap[e->print()];
        if (arr.empty()) {
            resolv->err(e, "alloc error for " + e->print());
        }
        auto res = arr[0];
        arr.erase(arr.begin());
        return res;
    }

    std::string getId(const std::string &name) {
        return name + "#" + std::to_string(resolv->max_scope);
    }

    llvm::Value *getVar(const std::string &name) {
        auto id = getId(name);
        auto it = NamedValues.find(id);
        if (it == NamedValues.end()) error("get var " + name);
        return it->second;
    }
    void addVar(const std::string &name, llvm::Value *ptr) {
        auto id = getId(name);
        NamedValues[id] = ptr;
    }

    llvm::Function *make_printf();
    llvm::Function *make_exit();
    llvm::Function *make_malloc();
    llvm::StructType *make_slice_type();
    llvm::StructType *make_string_type();

    llvm::Value *load(llvm::Value *val);
    llvm::Value *loadPtr(Expression *e);
    llvm::Value *loadPtr(std::unique_ptr<Expression> &e);
    llvm::Value *cast(Expression *expr, const Type &type);
    llvm::Type *mapType(const Type &t, Resolver *r);
    llvm::Type *mapType(const Type *t, Resolver *r) {
        return mapType(*t, r);
    }
    llvm::Type *mapType(const Type &t) { return mapType(&t); }
    llvm::Type *mapType(const Type *type) {
        return mapType(type, resolv.get());
    }
    llvm::DIType *map_di(const Type *t);
    llvm::DIType *map_di(const Type &t) { return map_di(&t); }
    void loc(Node *e);
    void loc(int line, int pos);
    void make_proto(std::unique_ptr<Method> &m);
    void make_proto(Method *m);
    llvm::Type *makeDecl(BaseDecl *bd);
    void allocParams(Method *m);
    void makeLocals(Statement *st);

    llvm::Value *gen(Expression *e);
    llvm::Value *gen(std::unique_ptr<Expression> &e);

    std::any visitParExpr(ParExpr *node) override;
    std::pair<llvm::Value *, llvm::BasicBlock *> andOr(Infix *node);
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
    void object(ObjExpr *node, llvm::Value *ptr, const RType &tt, std::string *derived);
    llvm::Value *call(MethodCall *node, llvm::Value *ptr);
    std::any slice(ArrayAccess *node, llvm::Value *ptr, const Type &arrty);
    void strLit(llvm::Value *ptr, Literal *lit);

    std::any visitBlock(Block *node) override;
    std::any visitVarDecl(VarDecl *node) override;
    std::any visitVarDeclExpr(VarDeclExpr *node) override;
    std::any visitReturnStmt(ReturnStmt *node) override;
    std::any visitExprStmt(ExprStmt *node) override;
    std::any visitIfStmt(IfStmt *node) override;
    std::any visitIfLetStmt(IfLetStmt *node) override;
    std::any visitAssertStmt(AssertStmt *node) override;
    std::any visitWhileStmt(WhileStmt *node) override;
    std::any visitForStmt(ForStmt *node) override;
    std::any visitContinueStmt(ContinueStmt *node) override;
    std::any visitBreakStmt(BreakStmt *node) override;
};