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

struct Config {
    static const bool optimize_enum = true;
};

class RType;
class Resolver;
class Signature;

bool isReturnLast(Statement *stmt);
bool isComp(const std::string &op);
RType binCast(const std::string &s1, const std::string &s2);

static int fieldIndex(std::vector<FieldDecl> &fields, const std::string &name, Type *type) {
    int i = 0;
    for (auto &fd : fields) {
        if (fd.name == name) {
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

static std::string printMethod(Method *m) {
    std::string s;
    std::string parent;
    if (m->parent) {
        if (m->parent->isImpl()) {
            auto impl = dynamic_cast<Impl *>(m->parent);
            parent = impl->type->print();
        } else if (m->parent->isTrait()) {
            auto t = dynamic_cast<Trait *>(m->parent);
            parent = t->type->print();
        }
    }
    if (!parent.empty()) {
        s += parent + "::";
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
        s += parent;
        i++;
    }
    for (auto &prm : m->params) {
        if (i > 0) s += ",";
        s += prm.type.get()->print();
    }
    s += ")";
    return s;
}

static std::string methodParent(Method *m) {
    if (!m->parent) return m->name;
    if (m->parent->isImpl()) {
        auto impl = dynamic_cast<Impl *>(m->parent);
        return impl->type->print() + "::" + m->name;
    } else if (m->parent->isTrait()) {
        auto t = dynamic_cast<Trait *>(m->parent);
        return t->type->print() + "::" + m->name;
    }
    return m->name;
}

static std::string mangle(Method *m) {
    std::string s = methodParent(m);

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
    if (m->parent && m->parent->isExtern()) return s;
    if (m->self) s += "_" + m->self->type->print();
    for (auto &prm : m->params) {
        s += "_" + prm.type.get()->print();
    }
    return s;
}

static std::string mangle_cpp(Method *m) {
    std::string s;
    if (m->name != "main") s += "_ZN";
    if (m->parent) {
        if (m->parent->isImpl()) {
            auto impl = dynamic_cast<Impl *>(m->parent);
            s += impl->type->print() + "::";
        } else if (m->parent->isTrait()) {
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
    if (m->parent && m->parent->isExtern()) return s;
    for (auto &prm : m->params) {
        s += "_" + prm.type.get()->print();
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

struct VarHolder {
    std::string name;
    Type *type;
    bool prm = false;

    VarHolder(std::string &name, Type *type, bool prm) : name(name), type(type), prm(prm) {}
    VarHolder(std::string &name, Type *type) : name(name), type(type) {}
};

class RType {
public:
    Unit *unit = nullptr;
    Type *type = nullptr;
    BaseDecl *targetDecl = nullptr;
    Method *targetMethod = nullptr;
    Trait *trait = nullptr;
    std::optional<VarHolder> vh;

    RType() = default;
    RType(Type *t) : type(t) {}
};

class Scope {
public:
    std::vector<VarHolder> list;

    void add(const VarHolder &f);
    void clear();
    VarHolder *find(const std::string &name);
};

//replace any type in decl with src by same index
class Generator : public AstCopier {
public:
    std::map<std::string, Type *> &map;

    Generator(std::map<std::string, Type *> &map) : map(map) {}
    std::any visitType(Type *type) override;
};

static std::string prm_id(Method &m, std::string &p) {
    return mangle(&m) + "." + p;
}

enum class MutKind {
    WHOLE,
    FIELD,
    DEREF
};

class Resolver : public Visitor {
public:
    std::shared_ptr<Unit> unit;
    std::unordered_map<std::string, RType> cache;
    std::unordered_map<std::string, RType> typeMap;
    std::vector<Scope> scopes;
    std::unordered_map<std::string, MutKind> mut_params;//todo
    Impl *curImpl = nullptr;
    Method *curMethod = nullptr;
    std::vector<Method *> generatedMethods;
    std::vector<BaseDecl *> genericTypes;
    bool inLoop = false;
    IdGen idgen;
    bool isResolved = false;
    bool is_init = false;
    std::vector<BaseDecl *> usedTypes;
    std::unordered_set<Method *> usedMethods;
    std::map<Method *, Method *> overrideMap;
    static std::unordered_map<std::string, std::shared_ptr<Resolver>> resolverMap;
    static std::vector<std::string> prelude;
    std::string root;

    explicit Resolver(std::shared_ptr<Unit> unit, const std::string &root);

    static std::shared_ptr<Resolver> getResolver(const std::string &path, const std::string &root);
    static std::shared_ptr<Resolver> getResolver(ImportStmt &is, const std::string &root);

    static int findVariant(EnumDecl *decl, const std::string &name);
    static bool is_simple_enum(EnumDecl *ed) {
        for (auto &ev : ed->variants) {
            if (ev.isStruct()) return false;
        }
        return true;
    }

    Method *isOverride(Method *method);
    static bool do_override(Method *m1, Method *m2);
    bool isCyclic(Type *type, BaseDecl *target);
    bool is_base_of(Type *base, BaseDecl *d);
    Type *inferStruct(ObjExpr *node, bool hasNamed, std::vector<Type *> &typeArgs, std::vector<FieldDecl> &fields, Type *type);
    std::vector<Method> &get_trait_methods(Type *type);
    std::unique_ptr<Impl> derive(BaseDecl *bd);
    std::vector<ImportStmt> get_imports();

    void newScope();
    void dropScope();
    Scope &curScope();

    void init();
    void resolveAll();

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
    RType getTypeCached(const std::string &name);
    void addType(const std::string &name, const RType &rt);
    std::string getId(Expression *e);
    BaseDecl *getDecl(Type *type);

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