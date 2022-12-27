#pragma once

#include "BaseVisitor.h"
#include "parser/Ast.h"
#include <map>
#include <memory>

class Symbol;
class RType;
class Resolver;

class Symbol {
public:
    Method *m = nullptr;
    Fragment *f = nullptr;
    FieldDecl *field = nullptr;
    Param *prm = nullptr;
    BaseDecl *decl = nullptr;
    ImportStmt *imp = nullptr;
    Resolver *resolver;

    Symbol(Method *m, Resolver *r) : m(m), resolver(r) {}
    Symbol(Fragment *f, Resolver *r) : f(f), resolver(r) {}
    Symbol(FieldDecl *f, Resolver *r) : field(f), resolver(r) {}
    Symbol(Param *prm, Resolver *r) : prm(prm), resolver(r) {}
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
    std::vector<Fragment *> list;
    //~Scope();
    void add(Fragment *f);
    void clear();
    Fragment *find(std::string &name);
};

class Resolver : public BaseVisitor<void *, void *> {
public:
    Unit *unit;
    std::map<BaseDecl *, RType *> declMap;
    std::map<Fragment *, RType *> varMap;
    std::map<Type *, RType *> typeMap;
    std::map<Param *, RType *> paramMap;
    std::map<Method *, RType *> methodMap;//return types
    //std::map<VarDecl*, RType*> fieldMap;
    std::map<Expression *, RType *> exprMap;
    std::vector<std::shared_ptr<Scope>> scopes;
    BaseDecl *curDecl = nullptr;
    Method *curMethod = nullptr;
    bool fromOther = false;
    static std::map<std::string, Resolver *> resolverMap;
    static std::string root;

    explicit Resolver(Unit *unit);
    virtual ~Resolver();

    static Resolver *getResolver(const std::string &path);
    void other(std::string name, std::vector<Symbol> &res) const;
    std::vector<Symbol> find(std::string &name, bool checkOthers);

    void dump();

    std::shared_ptr<Scope> curScope();
    void dropScope();

    void init();
    void resolveAll();

    void param(const std::string &name, std::vector<Symbol> &res);
    void field(const std::string &name, std::vector<Symbol> &res);
    void local(std::string name, std::vector<Symbol> &res);
    void method(const std::string &name, std::vector<Symbol> &res);
    RType *find(Type *type, BaseDecl *bd);

    RType *resolveType(Type *type);
    void *visitType(Type *type, void *arg) override;
    void *visitVarDeclExpr(VarDeclExpr *vd, void *arg) override;
    void *visitVarDecl(VarDecl *vd, void *arg) override;
    void *visitFragment(Fragment *f, void *arg) override;

    void *visitTypeDecl(TypeDecl *td, void *arg) override;
    void *visitEnumDecl(EnumDecl *ed, void *arg) override;
    void *visitBaseDecl(BaseDecl *bd, void *arg) override;
    RType *visitCommon(BaseDecl *bd);

    void *visitMethod(Method *m, void *arg) override;
    void *visitParam(Param *p, void *arg) override;

    RType *resolveScoped(Expression *expr);

    void *visitLiteral(Literal *lit, void *arg) override;
    void *visitInfix(Infix *infix, void *arg) override;
    void *visitAssign(Assign *as, void *arg) override;
    void *visitSimpleName(SimpleName *sn, void *arg) override;
    void *visitQName(QName *sn, void *arg) override;
    void *visitMethodCall(MethodCall *mc, void *arg) override;
    void *visitObjExpr(ObjExpr *o, void *arg) override;
    void *visitFieldAccess(FieldAccess *fa, void *arg) override;
    void *visitArrayCreation(ArrayCreation *ac, void *arg) override;
    void *visitAsExpr(AsExpr *as, void *arg) override;
    void *visitRefExpr(RefExpr *as, void *arg) override;
    void *visitDerefExpr(DerefExpr *as, void *arg) override;
};