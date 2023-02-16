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
class Signature;

bool isReturnLast(Statement *stmt);
bool isComp(const std::string &op);
RType binCast(const std::string &s1, const std::string &s2);

static int fieldIndex(std::vector<std::unique_ptr<FieldDecl>> &fields, const std::string &name, Type *type) {
    int i = 0;
    for (auto &fd : fields) {
        if (fd->name == name) {
            return i;
        }
        i++;
    }
    throw std::runtime_error("unknown field: " + type->print() + "." + name);
}
RType clone(const RType &rt);

static void error(const std::string &msg) {
    throw std::runtime_error(msg);
}

static std::vector<BaseDecl *> getTypes(Unit *unit) {
    std::vector<BaseDecl *> list;
    for (auto &item : unit->items) {
        if (item->isClass() || item->isEnum()) {
            list.push_back(dynamic_cast<BaseDecl *>(item.get()));
        }
    }
    return list;
}

static bool isMember(Method *m) {
    if (m->self) return true;
    return false;
}

// static std::string mangle(Type *type) {
//     if (type->isPointer()) {
//         auto ptr = dynamic_cast<PointerType *>(type);
//         return mangle(ptr->type) + "*";
//     }
//     std::string s = type->name;
//     if (!type->typeArgs.empty()) {
//         s.append("<");
//         int i = 0;
//         for (auto ta : type->typeArgs) {
//             if (i > 0) s.append(",");
//             s.append(mangle(ta));
//             i++;
//         }
//         s.append(">");
//     }
//     return s;
// }

static std::string printMethod(Method *m) {
    std::string s;
    if (m->parent) {
        if (m->parent->isImpl()) {
            auto impl = dynamic_cast<Impl *>(m->parent);
            s += impl->type->print() + "::";
        } else if(m->parent->isTrait()){
            auto t = dynamic_cast<Trait *>(m->parent);
            s += t->type->print() + "::";
        }
    }
    s += m->name;
    if (!m->typeArgs.empty()) {
        s += "<";
        for (int i = 0; i < m->typeArgs.size(); i++) {
            s += m->typeArgs[i]->print();
            if (i < m->typeArgs.size() - 1) {
                s += ",";
            }
        }
        s += ">";
    }
    s += "(";
    int i = 0;
    if (m->self) {
        s += m->self->type->print();
        i++;
    }
    for (auto &prm : m->params) {
        if (i > 0) s += ",";
        s += prm->type.get()->print();
    }
    s += ")";
    return s;
}

static std::string mangle(Method *m) {
    std::string s;
    if (m->parent) {
        if (m->parent->isImpl()) {
            auto impl = dynamic_cast<Impl *>(m->parent);
            s += impl->type->print() + "::";
        } else if(m->parent->isTrait()){
            auto t = dynamic_cast<Trait *>(m->parent);
            s += t->type->print() + "::";
        }
    }
    s += m->name;
    if (!m->typeArgs.empty()) {
        s += "<";
        for (int i = 0; i < m->typeArgs.size(); i++) {
            s += m->typeArgs[i]->print();
            if (i < m->typeArgs.size() - 1) {
                s += ",";
            }
        }
        s += ">";
    }
    //todo self
    if(m->parent &&m->parent->isExtern()) return s;
    for (auto &prm : m->params) {
        s += "_" + prm->type.get()->print();
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
    FieldDecl *decl;
    std::string name;
};

typedef std::variant<Fragment *, FieldDecl *, EnumPrm *, Param *> VarHolder;


class RType {
public:
    std::shared_ptr<Unit> unit;
    Type *type = nullptr;
    BaseDecl *targetDecl = nullptr;
    Method *targetMethod = nullptr;
    std::optional<VarHolder> vh;

    RType() = default;
    explicit RType(Type *t) : type(t) {}
};
static RType cast(std::any &&arg) {
    if (arg.type() == typeid(RType)) {
        return std::any_cast<RType>(arg);
    }
    throw std::runtime_error("unknown type");
}
class Symbol {
public:
    Method *m = nullptr;
    std::optional<VarHolder> v;
    BaseDecl *decl = nullptr;
    Resolver *resolver;

    Symbol(Method *m, Resolver *r) : m(m), resolver(r) {}
    Symbol(const VarHolder &f, Resolver *r) : v(f), resolver(r) {}
    Symbol(BaseDecl *bd, Resolver *r) : decl(bd), resolver(r) {}

    template<class T>
    RType resolve(T e) {
        return cast(e->accept(resolver));
    }
};
class Scope {
public:
    std::vector<VarHolder> list;
    //~Scope();
    void add(const VarHolder &f);
    void clear();
    std::optional<VarHolder> find(const std::string &name);
};

//replace any type in decl with src by same index
class Generator : public AstCopier {
public:
    std::map<std::string, Type *> &map;

    Generator(std::map<std::string, Type *> &map) : map(map) {}
    std::any visitType(Type *type) override;
};

class Resolver : public Visitor {
public:
    std::shared_ptr<Unit> unit;
    std::unordered_map<std::string, RType> cache;
    std::map<Fragment *, RType> varMap;
    std::map<std::string, RType> typeMap;
    std::map<std::string, RType> paramMap;
    std::unordered_map<Method *, RType> methodMap;
    std::vector<std::shared_ptr<Scope>> scopes;
    std::map<Method *, std::shared_ptr<Scope>> methodScopes;
    std::map<BaseDecl *, std::shared_ptr<Scope>> declScopes;
    std::unordered_set<Param *> mut_params;
    BaseDecl *curDecl = nullptr;
    Impl *curImpl = nullptr;
    Method *curMethod = nullptr;
    std::vector<Method *> generatedMethods;
    std::vector<BaseDecl *> genericTypes;
    bool fromOther = false;
    bool inLoop = false;
    IdGen *idgen;
    bool isResolved = false;
    std::vector<BaseDecl *> usedTypes;
    std::unordered_set<Method *> usedMethods;
    static std::unordered_map<std::string, std::shared_ptr<Resolver>> resolverMap;
    std::string root;

    explicit Resolver(std::shared_ptr<Unit> unit, const std::string &root);

    static std::shared_ptr<Resolver> getResolver(const std::string &path, const std::string &root);

    static int findVariant(EnumDecl *decl, const std::string &name);

    std::vector<Symbol> find(std::string &name, bool checkOthers);
    std::string getId(Expression *e);
    RType handleCallResult(std::vector<Signature> &list, Signature *sig);
    void findMethod(std::string& name, std::vector<Signature> &list);
    bool isCyclic(Type *type, BaseDecl *target);
    Type *inferStruct(ObjExpr *node, bool hasNamed, std::vector<Type *> &typeArgs, std::vector<std::unique_ptr<FieldDecl>> &fields, Type *type);

    void newScope();
    void dropScope();
    std::shared_ptr<Scope> curScope();

    void init();
    void resolveAll();

    RType getTypeCached(const std::string &name);
    void addType(const std::string &name, const RType &rt);

    std::any visitStructDecl(StructDecl *bd) override;
    std::any visitEnumDecl(EnumDecl *bd) override;
    std::any visitImpl(Impl *bd);
    std::any visitTrait(Trait *node);
    std::any visitExtern(Extern *node);
    std::any visitFieldDecl(FieldDecl *fd) override;
    std::any visitMethod(Method *m) override;
    std::any visitParam(Param *p) override;
    std::any visitType(Type *type) override;
    std::any visitVarDeclExpr(VarDeclExpr *vd) override;
    std::any visitVarDecl(VarDecl *vd) override;
    std::any visitFragment(Fragment *f) override;

    RType resolve(Expression *expr);
    Type *getType(Expression *expr);

    std::any visitLiteral(Literal *lit) override;
    std::any visitInfix(Infix *infix) override;
    std::any visitUnary(Unary *u) override;
    std::any visitAssign(Assign *as) override;
    std::any visitSimpleName(SimpleName *sn) override;
    std::any visitMethodCall(MethodCall *mc) override;
    std::any visitObjExpr(ObjExpr *o) override;
    std::any visitFieldAccess(FieldAccess *fa) override;
    std::any visitAsExpr(AsExpr *as) override;
    std::any visitRefExpr(RefExpr *as) override;
    std::any visitDerefExpr(DerefExpr *as) override;
    std::any visitParExpr(ParExpr *as) override;
    std::any visitArrayExpr(ArrayExpr *node) override;
    std::any visitIsExpr(IsExpr *as) override;
    std::any visitArrayAccess(ArrayAccess *node) override;

    std::any visitAssertStmt(AssertStmt *as) override;
    std::any visitIfLetStmt(IfLetStmt *as) override;
    std::any visitIfStmt(IfStmt *as) override;
    std::any visitExprStmt(ExprStmt *as) override;
    std::any visitBlock(Block *as) override;
    std::any visitReturnStmt(ReturnStmt *as) override;
    std::any visitWhileStmt(WhileStmt *node) override;
    std::any visitForStmt(ForStmt *node) override;
    std::any visitContinueStmt(ContinueStmt *node) override;
    std::any visitBreakStmt(BreakStmt *node) override;
};