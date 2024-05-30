#pragma once

#include "AstCopier.h"
#include "Ownership.h"
#include "Visitor.h"
#include "parser/Ast.h"
#include "parser/Util.h"
#include <iostream>
#include <map>
#include <memory>
#include <regex>
#include <unordered_map>
#include <unordered_set>
#include <variant>


constexpr int SLICE_LEN_BITS = 64;

static bool is_main(const Method *m) {
    //return m->name == "main" && m->params.empty();
    return m->name == "main" && (m->params.empty() || m->params.size() == 2);
}

struct Config {
    static bool optimize_enum;
    static bool verbose;
    static bool rvo_ptr;
    static bool debug;
    static bool use_cache;
    static std::string root;
};

class RType;
class Resolver;
class Signature;

bool isComp(const std::string &op);
RType binCast(const std::string &s1, const std::string &s2);

static bool is_ptr_get(MethodCall *mc) {
    return mc->is_static && mc->scope && mc->scope->print() == "ptr" && mc->name == "get";
}

static bool is_ptr_copy(MethodCall *mc) {
    return mc->is_static && mc->scope && mc->scope->print() == "ptr" && mc->name == "copy";
}

static bool is_ptr_deref(MethodCall *mc) {
    return mc->is_static && mc->scope && mc->scope->print() == "ptr" && mc->name == "deref";
}

static bool is_drop_call(MethodCall *mc) {
    return mc->name == "drop" && mc->scope && mc->scope->print() == "Drop" && mc->is_static;
}

static bool is_std_no_drop(MethodCall *mc) {
    return mc->name == "no_drop" && mc->scope && mc->scope->print() == "std" && mc->is_static;
}

static bool is_std_parent_name(MethodCall *mc) {
    return mc->name == "parent_name" && mc->scope && mc->scope->print() == "std" && mc->is_static;
}

static bool is_format(MethodCall *mc) {
    return mc->name == "format" && !mc->scope;
}
static bool is_printf(MethodCall *mc) {
    return mc->name == "printf" && !mc->scope;
}
static bool is_print(MethodCall *mc) {
    return mc->name == "print" && !mc->scope;
}
static bool is_panic(MethodCall *mc) {
    return mc->name == "panic" && !mc->scope;
}
static bool is_assert(MethodCall *mc) {
    return (mc->name == "assert" || mc->name == "assert_eq") && !mc->scope;
}

Literal *make_panic_messsage(const std::optional<std::string> &s, int line, Method *method);

static int fieldIndex(std::vector<FieldDecl> &fields, const std::string &name, const Type &type) {
    int i = 0;
    for (auto &fd : fields) {
        if (fd.name == name) {
            return i;
        }
        i++;
    }
    throw std::runtime_error("unknown field: " + type.print() + "." + name);
}

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

static std::vector<Type> get_type_params(Method &m) {
    std::vector<Type> res;
    if (!m.isGeneric) {
        return res;
    }
    if (!m.parent.is_none()) {
        res = m.parent.type_params;
    }
    res.insert(res.end(), m.typeArgs.begin(), m.typeArgs.end());
    return res;
}

static std::optional<Type> methodParent2(const Method *m) {
    if (m->parent.is_none()) return std::nullopt;
    if (m->parent.is_impl()) {
        return m->parent.type.value();
    } else if (m->parent.is_trait()) {
        return m->parent.type.value();
    }
    return std::nullopt;
}

static std::string methodParent(const Method *m) {
    auto p = methodParent2(m);
    if (p.has_value()) {
        return p.value().print() + "::" + m->name;
    } else {
        return m->name;
    }
}

static std::string printMethod(const Method *m) {
    std::string s = methodParent(m);
    if (!m->typeArgs.empty()) {
        s += "<";
        for (int i = 0; i < m->typeArgs.size(); i++) {
            s += m->typeArgs[i].print();
            if (i < m->typeArgs.size() - 1) {
                s += ",";
            }
        }
        s += ">";
    }
    s += "(";
    int i = 0;
    if (m->self) {
        if (m->self->type.has_value()) {
            s += m->self->type->print();
        } else {
            s += "self";
        }
        i++;
    }
    for (auto &prm : m->params) {
        if (i > 0) s += ",";
        s += prm.type->print();
        i++;
    }
    s += ")";
    return s;
}

static std::string mangleType(const Type &type) {
    auto s = type.print();
    s = std::regex_replace(s, std::regex("\\*"), "P");
    s = std::regex_replace(s, std::regex("<"), "$LT");
    s = std::regex_replace(s, std::regex(">"), "$GT");
    s = std::regex_replace(s, std::regex("::"), "__");
    return s;
}

static std::string mangle(const Method *m) {
    if (is_main(m)) return m->name;
    if (m->parent.is_extern()) return m->name;
    auto p = methodParent2(m);
    std::string s;
    if (p.has_value()) {
        s += mangleType(p.value());
        //s += "::";
        s += "__";
    }
    s += m->name;
    if (!m->typeArgs.empty()) {
        s += "$LT";
        for (int i = 0; i < m->typeArgs.size(); i++) {
            s += mangleType(m->typeArgs[i]);
            if (i < m->typeArgs.size() - 1) {
                s += ",";
            }
        }
        s += "$GT";
    }
    if (m->self) {
        s += "_" + mangleType(m->self->type.value());
    }
    for (auto &prm : m->params) {
        s += "_" + mangleType(prm.type.value());
    }
    return s;
}

static void print(const std::string &msg) {
    std::cout << msg << std::endl;
}

static bool isStruct(const Type &t) {
    return !t.isVoid() && !t.isPrim() && !t.isPointer();
}

struct VarHolder {
    std::string name;
    Type type;
    bool prm = false;
    int id;

    explicit VarHolder(std::string &name, const Type &type, bool prm, int id) : name(name), type(type), prm(prm), id(id) {}
    explicit VarHolder(std::string &name, const Type &type, int id) : name(name), type(type), id(id) {}
};

class RType {
public:
    Unit *unit = nullptr;
    Type type;
    BaseDecl *targetDecl = nullptr;
    Method *targetMethod = nullptr;
    Trait *trait = nullptr;
    std::optional<VarHolder> vh;
    std::optional<std::string> value;

    RType() = default;
    explicit RType(const Type &t) : type(t) {}

    RType clone();
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
    const std::map<std::string, Type> &map;

    explicit Generator(const std::map<std::string, Type> &map) : map(map){};

    static Type make(const Type &type, const std::map<std::string, Type> &map);

    std::any visitType(Type *type) override;
};

/*static std::string prm_id(const Method &m, const std::string &p) {
    return mangle(&m) + "." + p;
}*/

struct FormatInfo {
    Block block;
    MethodCall unwrap_mc;
    //MethodCall print_mc;
};

void generate_format(MethodCall *mc, Resolver *r);

struct Context {
    std::string root;
    std::unordered_map<std::string, std::shared_ptr<Resolver>> resolverMap;
    static std::vector<std::string> prelude;

    explicit Context(const std::string &root) : root(root) {}

    std::string getPath(ImportStmt &is) {
        return root + "/" + join(is.list, "/") + ".x";
    }

    std::shared_ptr<Resolver> getResolver(const std::string &path);
    std::shared_ptr<Resolver> getResolver(const ImportStmt &is);

    void init_prelude();
};

void generate_assert(MethodCall *mc, Resolver *r);

class Resolver : public Visitor {
public:
    std::shared_ptr<Unit> unit;
    std::unordered_map<int, RType> cache;
    std::unordered_map<std::string, RType> typeMap;
    std::vector<Scope> scopes;
    Impl *curImpl = nullptr;
    Method *curMethod = nullptr;
    std::vector<Method *> generatedMethods;
    int inLoop = 0;
    bool isResolved = false;
    bool is_init = false;
    std::vector<BaseDecl *> usedTypes;
    std::vector<std::unique_ptr<Impl>> generated_impl;
    std::map<std::string, Method *> drop_methods;
    std::map<int, FormatInfo> format_map;
    std::unordered_set<Method *> usedMethods;
    Context *context;

    explicit Resolver(std::shared_ptr<Unit> unit, Context *ctx) : unit(unit), context(ctx) {}
    ~Resolver() = default;

    void err(Node *e, const std::string &msg);
    void err(const std::string &msg);

    static int findVariant(EnumDecl *decl, const std::string &name);

    bool isCyclic(const Type &type, BaseDecl *target);
    bool is_base_of(const Type &base, BaseDecl *d);
    Type inferStruct(ObjExpr *node, bool hasNamed, const std::vector<Type> &typeArgs, std::vector<FieldDecl> &fields, const Type &type);
    std::vector<Method> &get_trait_methods(const Type &type);
    std::unique_ptr<Impl> derive_debug(BaseDecl *bd);
    std::unique_ptr<Impl> derive_drop(BaseDecl *bd);
    Method derive_drop_method(BaseDecl *bd);
    std::vector<ImportStmt> get_imports();

    void newScope();
    void dropScope();
    void addScope(std::string &name, const Type &type, bool prm, int line, int id);

    void init();
    void resolveAll();

    std::any visitStructDecl(StructDecl *bd) override;
    std::any visitEnumDecl(EnumDecl *bd) override;
    std::any visitImpl(Impl *bd) override;
    std::any visitTrait(Trait *node) override;
    std::any visitExtern(Extern *node) override;
    std::any visitFieldDecl(FieldDecl *fd) override;
    std::any visitMethod(Method *m) override;
    std::any visitParam(Param *p) override;
    std::any visitType(Type *type) override;
    std::any visitVarDeclExpr(VarDeclExpr *vd) override;
    std::any visitVarDecl(VarDecl *vd) override;
    std::any visitFragment(Fragment *f) override;

    RType resolve(Expression *expr);
    RType resolve(Ptr<Expression> &expr) {
        return resolve(expr.get());
    }
    RType resolve(const Type &type) {
        return resolve(const_cast<Type *>(&type));
    }
    Type getType(Expression *expr);
    Type getType(const Type &type) {
        return resolve(type).type;
    }
    RType getTypeCached(const std::string &name);
    void addType(const std::string &name, const RType &rt);
    //std::string getId(Expression *e);
    BaseDecl *getDecl(const Type &type);
    std::pair<StructDecl *, int> findField(const std::string &name, BaseDecl *decl);
    void addUsed(BaseDecl *bd);

    bool is_slice_get_ptr(MethodCall *mc) {
        if (!mc->scope || mc->name != "ptr" || !mc->args.empty()) {
            return false;
        }
        auto scope = getType(mc->scope.get()).unwrap();
        return scope.isSlice();
    }
    bool is_slice_get_len(MethodCall *mc) {
        if (!mc->scope || mc->name != "len" || !mc->args.empty()) {
            return false;
        }
        auto scope = getType(mc->scope.get()).unwrap();
        return scope.isSlice();
    }
    bool is_array_get_len(MethodCall *mc) {
        if (!mc->scope || mc->name != "len" || !mc->args.empty()) {
            return false;
        }
        auto scope = getType(mc->scope.get()).unwrap();
        return scope.isArray();
    }
    bool is_array_get_ptr(MethodCall *mc) {
        if (!mc->scope || mc->name != "ptr" || !mc->args.empty()) {
            return false;
        }
        auto scope = getType(mc->scope.get()).unwrap();
        return scope.isArray();
    }

    static bool is_std_size(MethodCall *mc) {
        return mc->scope && mc->scope->print() == "std" && mc->name == "size";
    }
    static bool is_std_is_ptr(MethodCall *mc) {
        return mc->scope && mc->scope->print() == "std" && mc->name == "is_ptr";
    }

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