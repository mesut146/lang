#pragma once

#include "AstCopier.h"
#include "IdGen.h"
#include "Visitor.h"
#include "parser/Ast.h"
#include <iostream>
#include <map>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <variant>

class Symbol;
class RType;
class Resolver;

bool isReturnLast(Statement *stmt);
bool isComp(const std::string &op);
RType *binCast(const std::string &s1, const std::string &s2);
int fieldIndex(TypeDecl *decl, const std::string &name);
int fieldIndex(EnumVariant *variant, const std::string &name);

static bool isMember(Method *m) {
    return m->parent && !m->isStatic;
}

static std::string mangle(Type *type) {
    return type->name;
}

static std::string mangle(Method *m) {
    std::string s;
    if (m->parent) {
        s += m->parent->name + "::";
    }
    s += m->name;
    for (auto prm : m->params) {
        s += "_" + mangle(prm->type.get());
    }
    return s;
}

static void print(const std::string &msg) {
    std::cout << msg << std::endl;
}

static bool isStruct(Type *t) {
    return !t->isPrim() && !t->isPointer();
}

static bool isRet(Statement *stmt) {
    auto expr = dynamic_cast<ExprStmt *>(stmt);
    if (expr) {
        auto mc = dynamic_cast<MethodCall *>(expr->expr);
        return mc && mc->name == "panic";
    }
    return dynamic_cast<ReturnStmt *>(stmt) || dynamic_cast<ContinueStmt *>(stmt) || dynamic_cast<BreakStmt *>(stmt);
}

class EnumPrm {
public:
    EnumParam *decl;
    std::string name;
};

typedef std::variant<Fragment *, FieldDecl *, EnumPrm *, Param *> VarHolder;

class Symbol {
public:
    Method *m = nullptr;
    VarHolder *v = nullptr;
    BaseDecl *decl = nullptr;
    ImportStmt *imp = nullptr;
    Resolver *resolver;

    Symbol(Method *m, Resolver *r) : m(m), resolver(r) {}
    Symbol(VarHolder *f, Resolver *r) : v(f), resolver(r) {}
    Symbol(BaseDecl *bd, Resolver *r) : decl(bd), resolver(r) {}
    Symbol(ImportStmt *imp, Resolver *r) : imp(imp), resolver(r) {}

    template<class T>
    RType *resolve(T e) {
        return (RType *) e->accept(resolver);
    }
};

class RType {
public:
    std::shared_ptr<Unit> unit;
    Type *type = nullptr;
    BaseDecl *targetDecl = nullptr;
    Method *targetMethod = nullptr;
    Fragment *targetVar = nullptr;
    VarHolder *vh = nullptr;
    bool isImport = false;
    std::vector<Symbol> arr;

    RType() = default;
    explicit RType(Type *t) : type(t) {}
};

class Scope {
public:
    std::vector<VarHolder *> list;
    //~Scope();
    void add(VarHolder *f);
    void clear();
    VarHolder *find(const std::string &name);
};

class Resolver : public Visitor {
public:
    std::shared_ptr<Unit> unit;
    std::unordered_map<std::string, RType *> cache;
    std::map<Fragment *, RType *> varMap;
    std::map<std::string, RType *> typeMap;
    std::map<std::string, RType *> paramMap;
    std::unordered_map<Method *, RType *> methodMap;
    std::vector<std::shared_ptr<Scope>> scopes;
    std::shared_ptr<Scope> globalScope;
    std::map<Method *, std::shared_ptr<Scope>> methodScopes;
    std::map<BaseDecl *, std::shared_ptr<Scope>> declScopes;
    std::unordered_set<Param *> mut_params;
    BaseDecl *curDecl = nullptr;
    Method *curMethod = nullptr;
    std::vector<Method *> genericMethods;
    std::vector<Method *> genericMethodsTodo;
    std::vector<BaseDecl *> genericTypes;
    bool fromOther = false;
    bool inLoop = false;
    IdGen *idgen;
    bool isResolved = false;
    std::vector<BaseDecl *> usedTypes;
    std::vector<Method *> usedMethods;
    static std::map<std::string, std::shared_ptr<Resolver>> resolverMap;
    std::string root;

    explicit Resolver(std::shared_ptr<Unit> unit, const std::string &root);
    virtual ~Resolver();
    static std::shared_ptr<Resolver> getResolver(const std::string &path, const std::string &root);

    static int findVariant(EnumDecl *decl, const std::string &name);

    void initDecl(BaseDecl *bd);
    void other(std::string name, std::vector<Symbol> &res) const;
    std::vector<Symbol> find(std::string &name, bool checkOthers);
    std::string getId(Expression *e);
    RType *handleCallResult(std::vector<Method *> &list, MethodCall *mc);

    void dump();

    void newScope();
    void dropScope();
    std::shared_ptr<Scope> curScope();

    void init();
    void resolveAll();

    RType *resolveType(Type *type);
    void *visitType(Type *type) override;
    void *visitVarDeclExpr(VarDeclExpr *vd) override;
    void *visitVarDecl(VarDecl *vd) override;
    void *visitFragment(Fragment *f) override;

    void *visitBaseDecl(BaseDecl *bd) override;
    void *visitFieldDecl(FieldDecl *fd) override;
    void *visitMethod(Method *m) override;
    void *visitParam(Param *p) override;
    //void *visitEnumParam(EnumParam *p) override;

    RType *resolve(Expression *expr);

    void *visitLiteral(Literal *lit) override;
    void *visitInfix(Infix *infix) override;
    void *visitUnary(Unary *u) override;
    void *visitAssign(Assign *as) override;
    void *visitSimpleName(SimpleName *sn) override;
    //void *visitQName(QName *sn) override;
    void *visitMethodCall(MethodCall *mc) override;
    void *visitObjExpr(ObjExpr *o) override;
    void *visitFieldAccess(FieldAccess *fa) override;
    void *visitAsExpr(AsExpr *as) override;
    void *visitRefExpr(RefExpr *as) override;
    void *visitDerefExpr(DerefExpr *as) override;
    void *visitAssertStmt(AssertStmt *as) override;
    void *visitIfLetStmt(IfLetStmt *as) override;
    void *visitIfStmt(IfStmt *as) override;
    void *visitParExpr(ParExpr *as) override;
    void *visitExprStmt(ExprStmt *as) override;
    void *visitBlock(Block *as) override;
    void *visitReturnStmt(ReturnStmt *as) override;
    void *visitIsExpr(IsExpr *as) override;
    void *visitArrayAccess(ArrayAccess *node) override;
    void *visitWhileStmt(WhileStmt *node) override;
    void *visitContinueStmt(ContinueStmt *node) override;
    void *visitBreakStmt(BreakStmt *node) override;
    void *visitArrayExpr(ArrayExpr *node) override;
};