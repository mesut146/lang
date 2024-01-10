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
void sort(std::vector<BaseDecl *> &list, Resolver *r);

constexpr int STRUCT_BASE_INDEX = 0;
constexpr int VPTR_INDEX = -1;//end
constexpr int ENUM_TAG_BITS = 64;
constexpr int ENUM_BASE_INDEX = 0;
constexpr int ENUM_TAG_INDEX = 1;
constexpr int ENUM_DATA_INDEX = 2;
constexpr int SLICE_PTR_INDEX = 0;
constexpr int SLICE_LEN_INDEX = 1;

struct Layout {
    static void set_elems_struct(llvm::StructType *st, llvm::Type *base, std::vector<llvm::Type *> &fields);
    static void set_elems_enum(llvm::StructType *st, llvm::Type *base, llvm::Type *tag, llvm::ArrayType *data);
    static int get_tag_index(BaseDecl *decl);
    static int get_data_index(BaseDecl *decl);
};

struct DebugInfo {
    llvm::DICompileUnit *cu;
    llvm::DIType *type;
    llvm::DIFile *file;
    llvm::DIScope *sp = nullptr;
    std::unordered_map<std::string, llvm::DIType *> types;
    std::unordered_map<std::string, llvm::DICompositeType *> incomplete_types;
};

struct Compiler : public Visitor {
public:
    std::string srcDir;
    std::string outDir;
    std::vector<std::string> compiled;
    std::shared_ptr<Unit> unit;
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
    std::map<int, std::vector<llvm::Value *>> allocMap2;
    std::map<std::string, llvm::Value *> NamedValues;
    std::map<std::string, llvm::Value *> varAlloc;
    std::map<std::string, llvm::Type *> classMap;
    std::map<std::string, llvm::Function *> funcMap;
    llvm::Function *printf_proto = nullptr;
    llvm::Function *fflush_proto = nullptr;
    llvm::GlobalVariable *stdout_ptr = nullptr;
    llvm::Function *exit_proto = nullptr;
    llvm::Function *mallocf = nullptr;
    llvm::StructType *sliceType = nullptr;
    llvm::StructType *stringType = nullptr;
    std::vector<Method *> virtuals;
    std::map<std::string, llvm::Constant *> vtables;
    std::map<Method *, int> virtualIndex;

    void set_and_insert(llvm::BasicBlock *bb);

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

    int getSize2(const Type *type);
    int getSize2(const Type &type) { return getSize2(&type); }
    int getSize2(BaseDecl *decl);
    void copy(llvm::Value *trg, llvm::Value *src, const Type &type);
    void setField(Expression *expr, const Type &type, llvm::Value *entPtr);
    llvm::Value *branch(llvm::Value *val);
    llvm::ConstantInt *makeInt(int val);
    llvm::ConstantInt *makeInt(int val, int bits);
    llvm::Type *getInt(int bit);
    void setOrdinal(int index, llvm::Value *ptr, BaseDecl *decl);
    void simpleVariant(const Type &n, llvm::Value *ptr);
    llvm::Value *getTag(Expression *expr);

    bool doesAlloc(Expression *e);
    llvm::Value *get_obj_ptr(Expression *e);
    bool need_alloc(const std::string &name, const Type &type);
    bool need_alloc(const Param &p) {
        return need_alloc(p.name, *p.type);
    }

    bool isRvo(Method *m) {
        return !m->type.isVoid() && isStruct(m->type);
    }

    bool isRvo(Expression *e) {
        auto m = resolv->resolve(e).targetMethod;
        return m && isRvo(m);
    }

    llvm::Type *getPtr() {
        return llvm::PointerType::getUnqual(ctx());
    }

    std::vector<llvm::Value *> makeIdx(int i1, int i2) {
        return {makeInt(i1, 64), makeInt(i2, 64)};
    }
    std::vector<llvm::Value *> makeIdx(int i1) {
        return {makeInt(i1, 64)};
    }
    llvm::Value *gep(llvm::Value *ptr, int i1, int i2, llvm::Type *type) {
        return gep(ptr, makeInt(i1, 64), makeInt(i2, 64), type);
    }
    llvm::Value *gep(llvm::Value *ptr, int i1, llvm::Type *type) {
        return gep(ptr, makeInt(i1, 64), type);
    }

    llvm::Value *gep(llvm::Value *ptr, llvm::Value *i1, llvm::Type *type) {
        std::vector<llvm::Value *> idx = {i1};
        if (type->isArrayTy()) {
            return Builder->CreateInBoundsGEP(type, ptr, idx);
        }
        return Builder->CreateGEP(type, ptr, idx);
    }
    llvm::Value *gep(llvm::Value *ptr, llvm::Value *i1, llvm::Value *i2, llvm::Type *type) {
        std::vector<llvm::Value *> idx = {i1, i2};
        if (type->isArrayTy()) {
            return Builder->CreateInBoundsGEP(type, ptr, idx);
        }
        return Builder->CreateGEP(type, ptr, idx);
    }
    llvm::Value *gep2(llvm::Value *ptr, int idx, llvm::Type *type) {
        return Builder->CreateStructGEP(type, ptr, idx);
        //return Builder->CreateConstInBoundsGEP1_64(type, ptr, idx);
    }
    llvm::Value *gep2(llvm::Value *ptr, int idx, const Type &type) {
        auto ty = mapType(type);
        return gep2(ptr, idx, ty);
    }
    llvm::Value *getAlloc(Expression *e) {
        /*if (e->id == -1) {
            resolv->err(e, "alloc no id");
        } else {
            resolv->err(e, "alloc id");
        }*/
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
    llvm::Function *make_fflush();
    llvm::Function *make_exit();
    llvm::Function *make_malloc();
    llvm::StructType *make_slice_type();
    llvm::StructType *make_string_type();

    llvm::Value *load(llvm::Value *val, const Type &type);
    llvm::Value *load(llvm::Value *val);
    llvm::Value *load(llvm::Value *val, llvm::Type *type) {
        return Builder->CreateLoad(type, val);
    }
    llvm::Value *loadPtr(Expression *e);
    llvm::Value *loadPtr(const std::unique_ptr<Expression> &e) {
        return loadPtr(e.get());
    }
    llvm::Value *cast(Expression *expr, const Type &type);
    llvm::Type *mapType(const Type &t, Resolver *r);
    llvm::Type *mapType(const Type *t, Resolver *r) {
        return mapType(*t, r);
    }
    llvm::Type *mapType(const Type &t) { return mapType(&t); }
    llvm::Type *mapType(const Type *type) {
        return mapType(type, resolv.get());
    }


    llvm::DIType *map_di0(const Type *t);
    llvm::DIType *map_di(const Type *t) {
        auto str = t->print();
        if (di.types.contains(str)) {
            return di.types.at(str);
        }
        auto res = map_di0(t);
        di.types.insert({str, res});
        return res;
    }
    llvm::DIType *map_di(const Type &t) { return map_di(&t); }
    void dbg_prm(Param &p, const Type &type, int idx);
    void dbg_var(const std::string &name, int line, int pos, const Type &type);
    void dbg_var(const Fragment &f, const Type &type) {
        dbg_var(f.name, f.line, f.pos, type);
    }
    static std::string dbg_name(Method *m);
    void dbg_func(Method *m, llvm::Function *func);

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