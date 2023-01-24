#include "Resolver.h"
#include "parser/Parser.h"
#include "parser/Util.h"
#include <list>
#include <memory>
#include <unordered_set>

void error(const std::string &msg) {
    throw std::runtime_error(msg);
}

bool isCondition(Expression *e, Resolver *r) {
    auto rt = r->resolve(e);
    return rt->type->print() == "bool";
}

bool isUnsigned(const std::string &s) {
    return s == "u8" || s == "u16" ||
           s == "u32" || s == "u64";
}

bool isComp(const std::string &op) {
    return op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=";
}

bool isType(Item *item) {
    return item->isClass() || item->isEnum();
}

template<class T>
bool iof(Expression *e) {
    return dynamic_cast<T>(e) != nullptr;
}

Type *clone(Type *type) {
    if (type->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(type);
        return new PointerType(clone(ptr->type));
    } else if (type->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(type);
        return new ArrayType(clone(arr->type), arr->size);
    } else if (type->isSlice()) {
        auto slice = dynamic_cast<SliceType *>(type);
        return new SliceType(clone(slice->type));
    } else {
        auto res = new Type(type->name);
        if (type->scope) {
            res->scope = clone(type->scope);
        }
        res->typeArgs.insert(res->typeArgs.end(), type->typeArgs.begin(), type->typeArgs.end());
        return res;
    }
}

RType *clone(RType *rt) {
    auto res = new RType;
    res->type = clone(rt->type);
    res->unit = rt->unit;
    res->targetDecl = rt->targetDecl;
    res->targetMethod = rt->targetMethod;
    res->targetVar = rt->targetVar;
    return res;
}

template<class T>
T copy(T arg) {
    AstCopier copier;
    return (T) arg->accept(&copier);
}

std::string normalize(const std::string &s) {
    if (s == "double") return "f64";
    if (s == "float") return "f32";
    if (s == "byte") return "i8";
    if (s == "short") return "i16";
    if (s == "char") return "u16";
    if (s == "int") return "i32";
    if (s == "long") return "i64";
    return s;
}

Type *simpleType(const std::string &name) {
    auto res = new Type;
    res->name = normalize(name);
    return res;
}

RType *makeSimple(const std::string &name) {
    auto res = new RType;
    res->type = simpleType(name);
    return res;
}

RType *binCast(const std::string &s1, const std::string &s2) {
    auto t1 = normalize(s1);
    auto t2 = normalize(s2);
    if (t1 == t2) {
        return makeSimple(s1);
    }
    if (t1 == "f64" || t2 == "f64") return makeSimple("f64");
    if (t1 == "f32" || t2 == "f32") return makeSimple("f32");
    if (t1 == "i64" || t2 == "i64") return makeSimple("i64");
    if (t1 == "i32" || t2 == "i32") return makeSimple("i32");
    if (t1 == "i16" || t2 == "i16") return makeSimple("i16");
    throw std::runtime_error("binCast");
}

bool subType(Type *type, Type *real) {
    if (type->print() == real->print()) return true;
    if (type->isVoid()) return false;
    if (type->isArray()) return false;
    if (type->isPrim()) {
        if (!real->isPrim()) return false;
        if (type->name == "bool") return false;
        // auto cast to larger size
        return sizeMap[type->name] <= sizeMap[real->name];
    }
    throw std::runtime_error("subtype " + type->print() + " sub: " + real->print());
}

std::shared_ptr<Resolver> Resolver::getResolver(const std::string &path, const std::string &root) {
    auto it = resolverMap.find(path);
    if (it != resolverMap.end()) return it->second;
    Lexer lexer(path);
    Parser parser(lexer);
    auto u = parser.parseUnit();
    u->path = path;
    auto resolver = std::make_shared<Resolver>(u, root);
    resolverMap[path] = resolver;
    return resolver;
}

//replace any type in decl with src by same index
class Generator : public AstCopier {
public:
    std::vector<Type *> &src;
    std::vector<Type *> &decl;

    Generator(std::vector<Type *> &src, std::vector<Type *> &decl) : src(src), decl(decl) {}

    void *visitType(Type *type) override {
        type = (Type *) AstCopier::visitType(type);
        if (type->isPointer()) {
            auto ptr = dynamic_cast<PointerType *>(type);
            ptr->type = (Type *) ptr->type->accept(this);
            return ptr;
        }
        for (auto &ta : type->typeArgs) {
            ta = (Type *) ta->accept(this);
        }
        auto str = type->print();
        for (int i = 0; i < decl.size(); i++) {
            if (decl[i]->print() == str) {
                return AstCopier::visitType(src[i]);
            }
        }
        return type;
    }
};

Method *generateMethod(std::vector<Type *> &typeArgs, Method *m) {
    auto gen = new Generator(typeArgs, m->typeArgs);
    auto res = (Method *) gen->visitMethod(m);
    res->typeArgs.clear();
    res->name = m->name;
    if (!m->parent) {
        /*res->name +="_";
        for (auto p : typeArgs) {
            res->name += p->print() + "_";
        }*/
    }
    return res;
}

int Resolver::findVariant(EnumDecl *decl, const std::string &name) {
    for (int i = 0; i < decl->variants.size(); i++) {
        if (decl->variants[i]->name == name) {
            return i;
        }
    }
    throw std::runtime_error("unknown variant: " + name + " of type " + decl->type->print());
}

std::string nameOf(VarHolder *vh) {
    auto f = std::get_if<Fragment *>(vh);
    if (f) return (*f)->name;
    auto p = std::get_if<Param *>(vh);
    if (p) return (*p)->name;
    auto fd = std::get_if<FieldDecl *>(vh);
    if (fd) return (*fd)->name;
    auto ep = std::get_if<EnumPrm *>(vh);
    return (*ep)->name;
}

void Scope::add(VarHolder *f) {
    for (auto prev : list) {
        if (nameOf(prev) == nameOf(f)) {
            throw std::runtime_error("variable " + nameOf(f) + " already declared in the same scope");
        }
    }
    list.push_back(f);
}

void Scope::clear() { list.clear(); }


VarHolder *Scope::find(const std::string &name) {
    for (auto vh : list) {
        if (nameOf(vh) == name) {
            return vh;
        }
    }
    return nullptr;
}

std::string Resolver::getId(Expression *e) {
    auto res = e->accept(idgen);
    if (res) {
        return *(std::string *) res;
    }
    throw std::runtime_error("id: " + e->print());
}

std::map<std::string, std::shared_ptr<Resolver>> Resolver::resolverMap;

Resolver::Resolver(std::shared_ptr<Unit> unit, const std::string &root) : unit(unit), root(root) {
    idgen = new IdGen(this);
}
Resolver::~Resolver() = default;


void Resolver::dump() {
    for (auto scope : scopes) {
        for (auto vh : scope->list) {
            std::cout << "scope var :" << nameOf(vh) << std::endl;
        }
    }
    for (auto f : varMap) {
        std::cout << "var: " << f.first->name << " = "
                  << f.second->type->print() << std::endl;
    }
}
void Resolver::newScope() {
    scopes.push_back(std::make_shared<Scope>());
}

void Resolver::dropScope() {
    //curScope()->clear();
    scopes.pop_back();
}

std::shared_ptr<Scope> Resolver::curScope() {
    return scopes.back();
}

void Resolver::resolveAll() {
    if (isResolved) return;
    isResolved = true;
    init();
    for (auto &i : unit->items) {
        i->accept(this);
    }
    for (auto gt : genericTypes) {
        gt->accept(this);
    }

    while (!genericMethodsTodo.empty()) {
        auto gm = genericMethodsTodo.back();
        genericMethodsTodo.pop_back();
        gm->accept(this);
        genericMethods.push_back(gm);
    }
}

void Resolver::init() {
    for (auto &item : unit->items) {
        if (!item->isClass() && !item->isEnum()) {
            continue;
        }
        auto bd = dynamic_cast<BaseDecl *>(item.get());
        if (!bd->type->typeArgs.empty()) {
            continue;
        }
        auto res = makeSimple(bd->getName());
        res->unit = unit;
        res->targetDecl = bd;
        typeMap[bd->getName()] = res;
    }
}

RType *Resolver::resolve(Expression *expr) {
    auto idtmp = expr->accept(idgen);
    if (!idtmp) {
        return (RType *) expr->accept(this);
    }
    auto id = *(std::string *) idtmp;
    auto it = cache.find(id);
    if (it != cache.end()) return it->second;
    auto res = (RType *) expr->accept(this);
    cache[id] = res;
    return res;
}

bool Resolver::isCyclic(Type *type, BaseDecl *target) {
    if (type->isPointer()) return false;
    if (type->isArray()) {
        auto at = dynamic_cast<ArrayType *>(type);
        return isCyclic(at->type, target);
    }
    if (type->isSlice()) return false;
    if (!isStruct(type)) return false;
    if (type->print() == target->type->print()) return true;
    auto bd = resolveType(type)->targetDecl;
    if (bd->isEnum()) {
        auto en = dynamic_cast<EnumDecl *>(bd);
        for (auto ev : en->variants) {
            for (auto f : ev->fields) {
                if (isCyclic(f->type, target)) return true;
            }
        }
    } else {
        auto td = dynamic_cast<StructDecl *>(bd);
        for (auto &fd : td->fields) {
            if (isCyclic(fd->type, target)) return true;
        }
    }
    return false;
}
void *Resolver::visitEnumDecl(EnumDecl *node) {
    if (node->isResolved) {
        error("already resolved");
    }
    node->isResolved = true;
    for (auto ev : node->variants) {
        for (auto ep : ev->fields) {
            ep->type->accept(this);
        }
    }
    curDecl = nullptr;
    return typeMap[node->getName()];
}
void *Resolver::visitStructDecl(StructDecl *node) {
    if (node->isResolved) {
        error("already resolved");
    }
    node->isResolved = true;
    curDecl = node;
    for (auto &fd : node->fields) {
        fd->accept(this);
    }
    curDecl = nullptr;
    return typeMap[node->getName()];
}

void *Resolver::visitImpl(Impl *node) {
    curImpl = node;
    for (auto &m : node->methods) {
        if (!m->typeArgs.empty()) {
            continue;
        }
        m->accept(this);
    }
    curImpl = nullptr;
    return resolve(node->type);
}

void *Resolver::visitFieldDecl(FieldDecl *node) {
    auto res = clone((RType *) node->type->accept(this));
    res->vh = new VarHolder(node);
    return res;
}

void *Resolver::visitMethod(Method *m) {
    if (m->isGeneric) {
        return nullptr;
    }

    auto it = methodMap.find(m);
    if (it != methodMap.end()) return it->second;
    curMethod = m;
    auto res = clone((RType *) m->type->accept(this));
    res->targetMethod = m;
    newScope();
    methodScopes[m] = curScope();
    if (m->self) {
        curScope()->add(new VarHolder(m->self.get()));
        if (curImpl) {
            m->self->type.reset(clone(curImpl->type));
        } else {
            m->self->type.reset(clone(curDecl->type));
        }
        m->self->accept(this);
    }
    for (auto prm : m->params) {
        curScope()->add(new VarHolder(prm));
        prm->accept(this);
    }
    if (m->body) {
        m->body->accept(this);
        //todo check unreachable
        if (!isReturnLast(m->body.get()) && !m->type->isVoid()) {
            error("non void function must return a value");
        }
    }
    dropScope();
    methodMap[m] = res;
    curMethod = nullptr;
    return res;
}

std::string paramId(Param *p) {
    if (p->method->parent) {
        if (isType(p->method->parent)) {
            auto bd = dynamic_cast<BaseDecl *>(p->method->parent);
            return bd->getName() + "#" + p->method->name + "#" + p->name;
        }
        if (p->method->parent->isImpl()) {
            auto impl = dynamic_cast<Impl *>(p->method->parent);
            return impl->type->print() + "#" + p->method->name + "#" + p->name;
        }
        throw std::runtime_error("paramId");
    } else {
        return p->method->name + "#" + p->name;
    }
}

void *Resolver::visitParam(Param *p) {
    auto id = paramId(p);
    if (paramMap.find(id) != paramMap.end()) return paramMap[id];
    auto res = clone(resolveType(p->type.get()));
    paramMap[id] = res;
    return res;
}

void *Resolver::visitFragment(Fragment *f) {
    auto it = varMap.find(f);
    if (it != varMap.end()) return it->second;
    RType *res = nullptr;
    if (f->type) {
        res = (RType *) f->type->accept(this);
    }
    auto rhs = resolve(f->rhs.get());
    if (!res) res = clone(rhs);
    res->targetVar = f;
    varMap[f] = res;
    //todo visit once
    curScope()->add(new VarHolder(f));
    return res;
}

void *Resolver::visitVarDeclExpr(VarDeclExpr *vd) {
    for (auto *f : vd->list) {
        f->accept(this);
    }
    return nullptr;
}

void *Resolver::visitVarDecl(VarDecl *vd) {
    visitVarDeclExpr(vd->decl);
    return nullptr;
}

BaseDecl *generateDecl(Type *type, BaseDecl *decl) {
    if (decl->isEnum()) {
        throw std::runtime_error("enum template");
    } else {
        auto res = new StructDecl;
        res->type = clone(type);
        /*res->type = new Type(decl->getName());
        for (auto ta : type->typeArgs) {
            res->type->name += "_" + ta->print();
        }*/
        auto td = dynamic_cast<StructDecl *>(decl);
        auto gen = new Generator(type->typeArgs, decl->type->typeArgs);
        // for (auto ta : type->typeArgs) {
        //     res->typeArgs.push_back((Type *) ta->accept(gen));
        // }
        for (auto &fd : td->fields) {
            auto type = (Type *) fd->type->accept(gen);
            auto field = new FieldDecl(fd->name, type, res);
            res->fields.push_back(std::unique_ptr<FieldDecl>(field));
        }
        //methods
        /*for (auto &m : td->methods) {
            auto method = (Method *) gen->visitMethod(m.get());
            method->parent = res;
            method->typeArgs.clear();
            res->methods.push_back(std::unique_ptr<Method>(method));
        }*/
        return res;
    }
}

void checkTypeArgs(std::vector<Type *> &arr1, std::vector<Type *> &arr2) {
    if (arr1.size() != arr2.size()) {
        error("type arguments size not matched");
    }
    for (int i = 0; i < arr1.size(); i++) {
        //todo
    }
}
void *Resolver::visitType(Type *type) {
    auto it = typeMap.find(type->print());
    if (it != typeMap.end()) return it->second;
    auto str = type->print();
    RType *res = nullptr;
    if (type->isPrim() || type->isVoid()) {
        if (isUnsigned(str)) {
            error("unsigned types not yet supported");
        }
        res = new RType(type);
        typeMap[str] = res;
        return res;
    }
    if (type->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(type);
        res = clone(resolveType(ptr->type));
        auto inner = res->type;
        auto pt = new PointerType(inner);
        res->type = pt;
        typeMap[str] = res;
        return res;
    }
    if (type->isSlice()) {
        auto slice = dynamic_cast<SliceType *>(type);
        auto inner = clone(resolveType(slice->type));
        res = new RType(new SliceType(inner->type));
        typeMap[str] = res;
        return res;
    }
    if (type->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(type);
        auto inner = clone(resolveType(arr->type));
        res = new RType(new ArrayType(inner->type, arr->size));
        typeMap[str] = res;
        return res;
    }
    if (type->scope == nullptr) {
        for (auto &bd : getTypes(unit.get())) {
            if (bd->getName() != type->name) {
                continue;
            }
            checkTypeArgs(type->typeArgs, bd->type->typeArgs);
            if (!bd->type->typeArgs.empty()) {
                auto decl = generateDecl(type, bd);
                if (decl->type->typeArgs[0]->name == "T") {
                    auto vv = 5;
                }
                print(decl->print());
                res = new RType;
                res->type = simpleType(type->name);
                for (auto ta : type->typeArgs) {
                    res->type->typeArgs.push_back(copy(ta));
                }
                res->targetDecl = decl;
                genericTypes.push_back(decl);
                typeMap[str] = res;
                typeMap[decl->type->print()] = res;
                return res;
            } else {
                return typeMap[bd->getName()];
            }
        }
        for (auto is : unit->imports) {
            auto resolver = getResolver(root + "/" + join(is->list, "/") + ".x", root);
            resolver->resolveAll();
            auto ii = resolver->typeMap.find(str);
            if (ii != resolver->typeMap.end()) {
                res = ii->second;
                typeMap[str] = res;
                usedTypes.push_back(res->targetDecl);
                return res;
            }
        }
        throw std::runtime_error("couldn't find type: " + str);
    }
    auto st = (RType *) type->scope->accept(this);
    auto bd = st->targetDecl;
    if (bd->isEnum()) {
        //enum variant creation
        auto ed = dynamic_cast<EnumDecl *>(bd);
        findVariant(ed, type->name);
        res = typeMap[ed->getName()];
    }
    if (!res) throw std::runtime_error("todo resolveType: " + str);
    typeMap[str] = res;
    return res;
}

//todo field mutation doesn't need alloc
Param *isMut(Expression *e, Resolver *r) {
    auto sn = dynamic_cast<SimpleName *>(e);
    if (sn) {
        auto rt = r->resolve(sn);
        if (std::get_if<Param *>(rt->vh) && isStruct(rt->type)) {
            return *std::get_if<Param *>(rt->vh);
        }
        return nullptr;
    }
    auto aa = dynamic_cast<ArrayAccess *>(e);
    if (aa) {
        return isMut(aa->array, r);
    }
    auto de = dynamic_cast<DerefExpr *>(e);
    if (de) {
        return isMut(de->expr, r);
    }
    auto fa = dynamic_cast<FieldAccess *>(e);
    if (fa) {
        //find root var
        auto scope = fa->scope;
        while (true) {
            auto fa2 = dynamic_cast<FieldAccess *>(scope);
            if (fa2) {
                scope = fa2->scope;
            } else {
                return isMut(scope, r);
            }
        }
    }
    throw std::runtime_error("todo isMut: " + e->print());
}

void *Resolver::visitAssign(Assign *as) {
    auto t1 = resolve(as->left);
    auto t2 = resolve(as->right);
    if (!subType(t2->type, t1->type)) {
        error("cannot assign " + as->right->print() + " to " + as->left->print());
    }
    auto prm = isMut(as->left, this);
    if (prm) {
        mut_params.insert(prm);
    }
    return t1;
}

void *Resolver::visitInfix(Infix *infix) {
    //auto id = getId(infix);
    //auto it = cache.find(id);
    //if (it != cache.end()) return it->second;
    //std::cout << "visitInfix = " << infix->print() << std::endl;
    auto rt1 = (RType *) infix->left->accept(this);
    auto rt2 = (RType *) infix->right->accept(this);
    if (rt1->type->isVoid() || rt2->type->isVoid()) {
        throw std::runtime_error("operation on void type");
    }
    if (rt1->type->isString() || rt2->type->isString()) {
        error("string op not supported yet");
    }
    if (!rt1->type->isPrim() || !rt2->type->isPrim()) {
        error("infix on non prim type: " + infix->print());
    }

    RType *res = nullptr;
    if (isComp(infix->op)) {
        res = makeSimple("bool");
    } else if (infix->op == "&&" || infix->op == "||") {
        if (rt1->type->print() != "bool") {
            error("infix lhs is not boolean: " + infix->left->print());
        }
        if (rt2->type->print() != "bool") {
            error("infix rhs is not boolean: " + infix->right->print());
        }
        res = makeSimple("bool");
    } else {
        auto s1 = rt1->type->print();
        auto s2 = rt2->type->print();
        res = binCast(s1, s2);
    }
    //cache[id] = res;
    return res;
}

void *Resolver::visitUnary(Unary *u) {
    //todo check unsigned
    auto res = resolve(u->expr);
    if (u->op == "!") {
        if (res->type->print() != "bool") {
            error("unary on non boolean: " + u->print());
        }
    } else {
        if (res->type->print() == "bool" || !res->type->isPrim()) {
            error("unary on non interal: " + u->print());
        }
        if (u->op == "--" || u->op == "++") {
            if (!iof<SimpleName *>(u->expr) && !iof<FieldAccess *>(u->expr)) {
                error("prefix on non variable: " + u->print());
            }
        }
    }
    return res;
}


RType *Resolver::resolveType(Type *type) {
    return (RType *) type->accept(this);
}

std::vector<Symbol> Resolver::find(std::string &name, bool checkOthers) {
    std::vector<Symbol> res;
    //params+locals+fields,globals
    for (int i = scopes.size() - 1; i >= 0; i--) {
        auto vh = scopes[i]->find(name);
        if (vh) {
            res.push_back(Symbol(vh, this));
        }
    }
    //imports(name, res, this);
    return res;
}
void *Resolver::visitSimpleName(SimpleName *sn) {
    auto id = getId(sn);
    auto it = cache.find(id);
    if (it != cache.end()) return it->second;

    auto arr = find(sn->name, true);
    if (arr.empty()) {
        throw std::runtime_error("unknown identifier: " + sn->name);
    }
    if (arr.size() > 1) {
        throw std::string("more than 1 result for ") + sn->name;
    }
    RType *res = nullptr;
    auto s = arr[0];
    if (s.v) {
        auto frag = std::get_if<Fragment *>(s.v);
        if (frag) {
            res = s.resolve(*frag);
        }
        auto prm = std::get_if<Param *>(s.v);
        if (prm) {
            res = s.resolve(*prm);
        }
        auto field = std::get_if<FieldDecl *>(s.v);
        if (field) {
            res = s.resolve(*field);
        }
        auto ep = std::get_if<EnumPrm *>(s.v);
        if (ep) {
            res = s.resolve((*ep)->decl->type);
        }
        res = clone(res);
        res->vh = s.v;
    } else if (s.m) {
        res = s.resolve(s.m);
    } else if (s.decl) {
        res = s.resolve(s.decl);
    } else if (s.imp) {
        res = new RType;
        res->arr.push_back(s);
    } else {
        throw std::runtime_error("unexpected state");
    }
    cache[id] = res;
    return res;
}

void *Resolver::visitFieldAccess(FieldAccess *fa) {
    RType *res = nullptr;
    auto scp = resolve(fa->scope);
    auto decl = scp->targetDecl;
    if (scp->isImport) {
        auto r = getResolver(scp->unit->path, root);
        auto tmp = r->find(fa->name, false);
        auto res = new RType;
        res->arr = tmp;
    } else if (decl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        if (fa->name != "index") {
            throw std::runtime_error("invalid field " + fa->name + " in " +
                                     scp->type->print());
        }
        res = makeSimple("int");
    } else {
        auto td = dynamic_cast<StructDecl *>(decl);
        int i = fieldIndex(td, fa->name);
        auto &fd = td->fields[i];
        res = (RType *) fd->accept(this);
    }
    if (res) {
        return res;
    }
    throw std::runtime_error("invalid field " + fa->name + " in " +
                             scp->type->print());
}

void *Resolver::visitLiteral(Literal *lit) {
    auto res = new RType;
    auto type = new Type;
    res->type = type;
    if (lit->type == Literal::STR) {
        type->scope = simpleType("core");
        type->name = "string";
    } else if (lit->type == Literal::BOOL) {
        type->name = "bool";
    } else if (lit->type == Literal::FLOAT) {
        type->name = "float";
    } else if (lit->type == Literal::INT) {
        type->name = "int";
    } else if (lit->type == Literal::CHAR) {
        type->name = "char";
    }
    return res;
}


std::string toPath(std::vector<std::string> &list) {
    return join(list, "/");
}

void imports(std::string &name, std::vector<Symbol> &res, Resolver *r) {
    for (auto is : r->unit->imports) {
    }
}

void Resolver::other(std::string name, std::vector<Symbol> &res) const {
    for (auto *is : unit->imports) {
        auto r = getResolver(root + "/" + toPath(is->list), root);
        r->fromOther = true;
        auto arr = r->find(name, false);
        r->fromOther = false;
        res.insert(res.end(), arr.begin(), arr.end());
    }
}

void *Resolver::visitAsExpr(AsExpr *e) {
    auto left = (RType *) e->expr->accept(this);
    auto right = (RType *) e->type->accept(this);
    //prim->prim
    if (!left->type->isPrim() || left->type->isVoid()) {
        error("as expr must be primitive: " + e->expr->print());
    }
    if (!right->type->isPrim() || right->type->isVoid()) {
        error("as type must be primitive: " + e->type->print());
    }
    return right;
}

void *Resolver::visitRefExpr(RefExpr *e) {
    //todo field access
    if (!iof<SimpleName *>(e->expr)) {
        error("ref expr is not supported: " + e->expr->print());
    }
    auto inner = clone((RType *) e->expr->accept(this));
    auto ptr = new PointerType(inner->type);
    inner->type = ptr;
    return inner;
}

void *Resolver::visitDerefExpr(DerefExpr *e) {
    auto res = clone((RType *) e->expr->accept(this));
    auto inner = res->type;
    if (!inner->isPointer()) error("deref expr is not pointer: " + e->expr->print());
    auto ptr = dynamic_cast<PointerType *>(inner);
    res->type = ptr->type;
    return res;
}

void *Resolver::visitAssertStmt(AssertStmt *st) {
    if (!isCondition(st->expr.get(), this)) {
        error("assert expr is not boolean expr: " + st->expr->print());
    }
    return nullptr;
}

void *Resolver::visitIfLetStmt(IfLetStmt *st) {
    newScope();
    auto rt = (RType *) st->type->scope->accept(this);
    if (!rt->targetDecl->isEnum()) {
        error("type of if let is not enum: " + st->type->scope->print());
    }
    auto decl = dynamic_cast<EnumDecl *>(rt->targetDecl);
    int index = findVariant(decl, st->type->name);
    auto variant = decl->variants[index];
    int i = 0;
    for (auto &name : st->args) {
        auto ep = variant->fields[i];
        auto tmp = new EnumPrm;
        tmp->decl = ep;
        tmp->name = name;
        curScope()->add(new VarHolder(tmp));
        i++;
    }
    auto rhs = resolve(st->rhs.get());
    if (!rhs->targetDecl->isEnum()) {
        error("if let rhs is not enum: " + st->rhs->print());
    }
    st->thenStmt->accept(this);
    dropScope();
    if (st->elseStmt) {
        st->elseStmt->accept(this);
    }
    return nullptr;
}

void *Resolver::visitParExpr(ParExpr *e) {
    return e->expr->accept(this);
}

void *Resolver::visitExprStmt(ExprStmt *node) {
    if (!iof<MethodCall *>(node->expr) && !iof<Assign *>(node->expr) && !iof<Unary *>(node->expr) && !iof<Postfix *>(node->expr)) {
        error("invalid expr statement: " + node->print());
    }
    node->expr->accept(this);
    return nullptr;
}

void *Resolver::visitBlock(Block *node) {
    int i = 0;
    for (auto &st : node->list) {
        if (i > 0 && isRet(node->list[i - 1].get())) {
            error("unreachable code: " + st->print());
        }
        st->accept(this);
        i++;
    }
    return nullptr;
}

void *Resolver::visitIfStmt(IfStmt *node) {
    if (!isCondition(node->expr.get(), this)) {
        error("if condition is not a boolean");
    }
    node->thenStmt->accept(this);
    if (node->elseStmt) node->elseStmt->accept(this);
    return nullptr;
}

void *Resolver::visitReturnStmt(ReturnStmt *st) {
    if (st->expr) {
        if (curMethod->type->isVoid()) {
            error("void method returns expr");
        }
        auto type = (RType *) st->expr->accept(this);
        if (!subType(type->type, curMethod->type.get())) {
            error("method expects '" + curMethod->type->print() + " but returned '" + type->type->print() + "'");
        }
    } else {
        if (!curMethod->type->isVoid()) {
            error("non-void method returns void");
        }
    }
    return nullptr;
}

void *Resolver::visitIsExpr(IsExpr *ie) {
    auto rt = resolve(ie->expr);
    auto decl1 = rt->targetDecl;
    if (!decl1->isEnum()) {
        error("lhs of is expr is not enum");
    }
    auto rt2 = resolve(ie->type->scope);
    auto decl2 = rt2->targetDecl;
    if (decl1 != decl2) {
        error("rhs of is expr is not enum");
    }
    findVariant(dynamic_cast<EnumDecl *>(decl1), ie->type->name);
    return makeSimple("bool");
}

void *Resolver::visitObjExpr(ObjExpr *o) {
    bool hasNamed = false;
    bool hasNonNamed = false;
    for (auto &e : o->entries) {
        if (e.hasKey()) {
            hasNamed = true;
        } else {
            hasNonNamed = true;
        }
    }
    if (hasNamed && hasNonNamed) {
        throw std::runtime_error("obj creation can't have mixed values");
    }
    auto res = resolveType(o->type.get());
    if (o->isPointer) {
        res = clone(res);
        res->type = new PointerType(res->type);
    }
    if (res->targetDecl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(res->targetDecl);
        int idx = findVariant(ed, o->type->name);
        auto variant = ed->variants[idx];
        if (variant->fields.size() != o->entries.size()) {
            error("incorrect number of arguments passed to enum creation");
        }
        std::unordered_set<std::string> names;
        for (int i = 0; i < o->entries.size(); i++) {
            auto &e = o->entries[i];
            int prm_idx;
            if (hasNamed) {
                names.insert(e.key);
                prm_idx = fieldIndex(variant, e.key);
            } else {
                prm_idx = i;
            }
            auto prm = variant->fields[i];
            auto vt = resolve(prm->type);
            auto val = resolve(e.value);
            if (!subType(val->type, prm->type)) {
                error("variant field type is imcompatiple with " + e.value->print());
            }
        }
        if (hasNamed) {
            for (auto p : variant->fields) {
                if (names.find(p->name) == names.end()) {
                    error("field not covered: " + p->name);
                }
            }
        }
    } else {
        auto td = dynamic_cast<StructDecl *>(res->targetDecl);
        if (td->fields.size() != o->entries.size()) {
            error("incorrect number of arguments passed to class creation");
        }
        std::unordered_set<std::string> names;
        for (int i = 0; i < o->entries.size(); i++) {
            auto &e = o->entries[i];
            int prm_idx;
            if (hasNamed) {
                names.insert(e.key);
                prm_idx = fieldIndex(td, e.key);
            } else {
                prm_idx = i;
            }
            auto &prm = td->fields[i];
            auto vt = resolve(prm->type);
            auto val = resolve(e.value);
            if (!subType(val->type, prm->type)) {
                error("variant field type is imcompatiple with " + e.value->print());
            }
        }
        if (hasNamed) {
            for (auto &p : td->fields) {
                if (names.find(p->name) == names.end()) {
                    error("field not covered: " + p->name);
                }
            }
        }
    }
    return res;
}

void *Resolver::visitArrayAccess(ArrayAccess *node) {
    auto arr = resolve(node->array);
    auto idx = resolve(node->index);
    //todo unsigned
    if (idx->type->print() == "bool" || !idx->type->isPrim()) error("array index is not an integer");
    if (node->index2) {
        auto idx2 = resolve(node->index2.get());
        if (idx2->type->print() == "bool" || !idx2->type->isPrim()) error("range end is not an integer");
        auto at = dynamic_cast<ArrayType *>(arr->type);
        return new RType(new SliceType(at->type));
    }
    if (arr->type->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(arr->type);
        auto res = resolveType(ptr->type);
        if (res->type->isArray() || res->type->isSlice()) {
            arr = res;
        } else {
            return res;
        }
    }
    if (arr->type->isArray()) {
        auto at = dynamic_cast<ArrayType *>(arr->type);
        return resolveType(at->type);
    }
    if (arr->type->isSlice()) {
        auto at = dynamic_cast<SliceType *>(arr->type);
        return resolveType(at->type);
    }
    throw std::runtime_error("array expr is not a pointer: " + node->print());
}

bool isSame(Resolver *r, MethodCall *mc, Method *m) {
    if (mc->name != m->name) return false;
    if (mc->args.size() != m->params.size()) return false;
    if (!mc->typeArgs.empty()) return !m->typeArgs.empty();
    for (int i = 0; i < mc->args.size(); i++) {
        auto t1 = r->resolve(mc->args[i]);
        auto t2 = (RType *) m->params[i]->accept(r);
        if (!subType(t1->type, t2->type)) return false;
    }
    return true;
}

std::vector<Method *> filter(Resolver *r, std::vector<Method *> &list, MethodCall *mc) {
    std::vector<Method *> res;
    for (auto m : list) {
        if (isSame(r, mc, m)) {
            res.push_back(m);
        }
    }
    return res;
}

void Resolver::getMethods(Type *type, std::string &name, std::vector<Method *> &list) {
    for (auto &i : unit->items) {
        if (i->isImpl()) {
            auto impl = dynamic_cast<Impl *>(i.get());
            if (impl->type->name != type->name) continue;
            if (!impl->type->typeArgs.empty()) resolve(type);
            for (auto &m : impl->methods) {
                if (m->name == name) list.push_back(m.get());
            }
        }
    }
}

RType *scopedMethod(MethodCall *mc, Resolver *r) {
    auto scope = r->resolve(mc->scope.get());
    std::vector<Method *> list;
    r->getMethods(scope->type, mc->name, list);
    return r->handleCallResult(list, mc);
}

void findMethod(Unit *unit, std::string &name, std::vector<Method *> &list) {
    for (auto &item : unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            if (m->name == name) {
                list.push_back(m);
            }
        }
    }
}

RType *Resolver::handleCallResult(std::vector<Method *> &list, MethodCall *mc) {
    if (list.empty()) {
        error("no such method: " + mc->name);
    }
    auto real = filter(this, list, mc);
    if (real.empty()) {
        //print cand
        throw std::runtime_error("method: " + mc->name + " not found from candidates: ");
    }
    if (real.size() > 1) {
        throw std::runtime_error("method:  " + mc->name + " has " +
                                 std::to_string(list.size()) + " candidates");
    }
    auto target = real[0];
    if (!target->typeArgs.empty()) {
        auto newMethod = generateMethod(mc->typeArgs, target);
        genericMethodsTodo.push_back(newMethod);
        target = newMethod;
    }
    auto res = clone(resolveType(target->type.get()));
    res->targetMethod = target;
    if (target->unit != unit.get()) {
        usedMethods.push_back(target);
    }
    return res;
}

void *Resolver::visitMethodCall(MethodCall *mc) {
    auto id = getId(mc);
    auto it = cache.find(id);
    if (it != cache.end()) return it->second;
    for (auto arg : mc->args) {
        resolve(arg);
    }
    if (mc->scope) {
        auto res = scopedMethod(mc, this);
        cache[id] = res;
        return res;
    }
    if (mc->name == "print") {
        return makeSimple("void");
    } else if (mc->name == "malloc") {
        Type *in;
        if (mc->typeArgs.empty()) {
            in = simpleType("i8");
        } else {
            in = resolveType(mc->typeArgs[0])->type;
        }
        auto res = new RType;
        res->type = new PointerType(in);
        return res;
    } else if (mc->name == "panic") {
        if (mc->args.empty()) {
            auto res = new RType(new Type("void"));
            return res;
        }
        auto lit = dynamic_cast<Literal *>(mc->args[0]);
        if (lit && lit->type == Literal::STR) {
            auto res = new RType(new Type("void"));
            return res;
        }
        throw std::runtime_error("invalid panic argument: " + mc->args[0]->print());
    }
    std::vector<Method *> cand;// candidates
    findMethod(unit.get(), mc->name, cand);
    if (curImpl) {
        //static sibling
        for (auto &m : curImpl->methods) {
            if (!m->self && m->name == mc->name) {
                cand.push_back(m.get());
            }
        }
    }
    for (auto is : unit->imports) {
        auto resolver = getResolver(root + "/" + join(is->list, "/") + ".x", root);
        resolver->resolveAll();
        findMethod(resolver->unit.get(), mc->name, cand);
    }
    auto res = handleCallResult(cand, mc);
    cache[id] = res;
    return res;
}

void *Resolver::visitWhileStmt(WhileStmt *node) {
    if (!isCondition(node->expr.get(), this)) error("while statement expr is not a condition");
    inLoop = true;
    node->body->accept(this);
    inLoop = false;
    return nullptr;
}

void *Resolver::visitContinueStmt(ContinueStmt *node) {
    if (!inLoop) {
        error("continue in outside of loop");
    }
    if (node->label) error("continue label");
    return nullptr;
}

void *Resolver::visitBreakStmt(BreakStmt *node) {
    if (!inLoop) {
        error("break in outside of loop");
    }
    if (node->label) error("break label");
    return nullptr;
}

void *Resolver::visitArrayExpr(ArrayExpr *node) {
    if (node->isSized()) {
        auto elemType = resolve(node->list[0]);
        return new RType(new ArrayType(elemType->type, node->size.value()));
    } else {
        auto inner = resolve(node->list[0]);
        for (int i = 1; i < node->list.size(); i++) {
            auto t = resolve(node->list[i]);
            if (!subType(inner->type, t->type)) {
                error("array element type mismatch");
            }
        }
        return new RType(new ArrayType(inner->type, node->list.size()));
    }
}