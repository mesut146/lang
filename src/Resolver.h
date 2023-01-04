#pragma once

#include "BaseVisitor.h"
#include "parser/Ast.h"
#include <map>
#include <memory>
#include <unordered_map>
#include <variant>

class Symbol;
class RType;
class Resolver;

static std::map<std::string, int> sizeMap{
        {"bool", 1},
        {"i8", 8},
        {"i16", 16},
        {"i32", 32},
        {"i64", 64},
        {"u16", 16},
        {"u8", 8},
        {"u16", 16},
        {"u32", 32},
        {"u64", 64},
        {"byte", 8},
        {"char", 16},
        {"short", 16},
        {"int", 32},
        {"long", 64},
        {"float", 32},
        {"double", 64}};

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
        return (RType *) e->accept(resolver, nullptr);
    }
};

class RType {
public:
    Unit *unit = nullptr;
    Type *type = nullptr;
    BaseDecl *targetDecl = nullptr;
    Method *targetMethod = nullptr;
    Fragment *targetVar = nullptr;
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

class Resolver : public Visitor<void *, void *> {
public:
    Unit *unit;
    std::map<Fragment *, RType *> varMap;
    std::map<std::string, RType *> typeMap;
    std::map<Param *, RType *> paramMap;
    //std::map<EnumParam *, RType *> paramMap;
    std::unordered_map<Method *, RType *> methodMap;//return types
    //std::map<FieldDecl*, RType*> fieldMap;
    std::unordered_map<Expression *, RType *> exprMap;
    std::vector<std::shared_ptr<Scope>> scopes;
    BaseDecl *curDecl = nullptr;
    Method *curMethod = nullptr;
    bool fromOther = false;
    static std::map<std::string, Resolver *> resolverMap;
    static std::string root;

    explicit Resolver(Unit *unit);
    virtual ~Resolver();

    static int findVariant(EnumDecl *decl, const std::string &name);

    static Resolver *getResolver(const std::string &path);
    void other(std::string name, std::vector<Symbol> &res) const;
    std::vector<Symbol> find(std::string &name, bool checkOthers);

    void dump();

    void newScope();
    void dropScope();
    std::shared_ptr<Scope> curScope();

    void init();
    void resolveAll();

    RType *resolveType(Type *type);
    void *visitType(Type *type, void *arg) override;
    void *visitVarDeclExpr(VarDeclExpr *vd, void *arg) override;
    void *visitVarDecl(VarDecl *vd, void *arg) override;
    void *visitFragment(Fragment *f, void *arg) override;

    void *visitBaseDecl(BaseDecl *bd, void *arg) override;
    void *visitFieldDecl(FieldDecl *fd, void *arg) override;

    void *visitMethod(Method *m, void *arg) override;
    void *visitParam(Param *p, void *arg) override;
    //void *visitEnumParam(EnumParam *p, void *arg) override;

    RType *resolveScoped(Expression *expr);

    void *visitLiteral(Literal *lit, void *arg) override;
    void *visitInfix(Infix *infix, void *arg) override;
    void *visitAssign(Assign *as, void *arg) override;
    void *visitSimpleName(SimpleName *sn, void *arg) override;
    //void *visitQName(QName *sn, void *arg) override;
    void *visitMethodCall(MethodCall *mc, void *arg) override;
    void *visitObjExpr(ObjExpr *o, void *arg) override;
    void *visitFieldAccess(FieldAccess *fa, void *arg) override;
    void *visitArrayCreation(ArrayCreation *ac, void *arg) override;
    void *visitAsExpr(AsExpr *as, void *arg) override;
    void *visitRefExpr(RefExpr *as, void *arg) override;
    void *visitDerefExpr(DerefExpr *as, void *arg) override;
    void *visitAssertStmt(AssertStmt *as, void *arg) override;
    void *visitIfLetStmt(IfLetStmt *as, void *arg) override;
    void *visitIfStmt(IfStmt *as, void *arg) override;
    void *visitParExpr(ParExpr *as, void *arg) override;
    void *visitExprStmt(ExprStmt *as, void *arg) override;
    void *visitBlock(Block *as, void *arg) override;
    void *visitReturnStmt(ReturnStmt *as, void *arg) override;
    void *visitIsExpr(IsExpr *as, void *arg) override;
};