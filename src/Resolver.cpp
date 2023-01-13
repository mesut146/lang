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

template<class T>
bool iof(Expression *e) {
    return dynamic_cast<T>(e) != nullptr;
}

Type *clone(Type *type) {
    if (type->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(type);
        auto res = new PointerType(clone(ptr->type));
        return res;
    } else if (type->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(type);
        auto res = new ArrayType;
        res->type = clone(arr->type);
        res->dims.insert(res->dims.end(), arr->dims.begin(), arr->dims.end());
        return res;
    } else {
        auto res = new Type;
        if (type->scope) {
            res->scope = clone(type->scope);
        }
        res->name = type->name;
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
        if (sizeMap[type->name] <= sizeMap[real->name]) {
            return true;
        } else {
            return false;
        }
    }
    // upcast
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
    if (m->parent) {
        res->name = m->name;
    } else {
        res->name = m->name + "_";
        for (auto p : typeArgs) {
            res->name += p->print() + "_";
        }
    }
    return res;
}
int Resolver::findVariant(EnumDecl *decl, const std::string &name) {
    for (int i = 0; i < decl->variants.size(); i++) {
        if (decl->variants[i]->name == name) {
            return i;
        }
    }
    throw std::runtime_error("unknown variant: " + name + " of type " + decl->name);
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
            std::runtime_error("variable " + nameOf(f) + " already declared in the same scope");
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
    /*for(auto &p : fieldMap){
      std::cout << "field: " << p.first->name << " = " <<
    p.second->type->print() << "\n";
    }*/
    for (auto &p : methodMap) {
        std::cout << "method: " << p.first->name << " = "
                  << p.second->type->print() << std::endl;
        for (auto *prm : p.first->params) {
            std::cout << "param: " << prm->name << " = "
                      << paramMap[prm]->type->print() << std::endl;
        }
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
    for (auto &st : unit->stmts) {
        st->accept(this);
    }
    for (auto m : unit->methods) {
        if (!m->typeArgs.empty()) {
            continue;
        }
        visitMethod(m);
    }
    for (auto bd : unit->types) {
        if (!bd->typeArgs.empty()) {
            continue;
        }
        newScope();
        visitBaseDecl(bd);
        for (auto m : bd->methods) {
            if (!m->typeArgs.empty()) {
                continue;
            }
            curDecl = bd;
            visitMethod(m);
            curDecl = nullptr;
        }
        dropScope();
    }
    for (auto gt : genericTypes) {
        newScope();
        visitBaseDecl(gt);
        curDecl = gt;
        for (auto m : gt->methods) {
            visitMethod(m);
        }
        curDecl = nullptr;
        dropScope();
    }
    while (!genericMethodsTodo.empty()) {
        auto gm = genericMethodsTodo.back();
        genericMethodsTodo.pop_back();
        gm->accept(this);
        genericMethods.push_back(gm);
    }
    //dropScope();//global
}

void Resolver::init() {
    for (auto bd : unit->types) {
        if (!bd->typeArgs.empty()) {
            continue;
        }
        auto res = makeSimple(bd->name);
        res->unit = unit;
        res->targetDecl = bd;
        typeMap[bd->name] = res;
    }
    // for (auto m : unit->methods) {
    //     if (!m->typeArgs.empty()) {
    //         continue;
    //     }
    //     auto res = clone(resolve(m->type.get()));
    //     res->targetMethod = m;
    //     methodMap[m] = res;
    // }
    // for (auto bd : unit->types) {
    //     if (!bd->typeArgs.empty()) {
    //         continue;
    //     }
    //     for (auto m : bd->methods) {
    //         if (!m->typeArgs.empty()) {
    //             continue;
    //         }
    //         auto res = clone(resolve(m->type.get()));
    //         res->targetMethod = m;
    //         methodMap[m] = res;
    //     }
    // }
    newScope();//globals
    globalScope = curScope();
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

void *Resolver::visitBaseDecl(BaseDecl *bd) {
    bd->isResolved = true;
    curDecl = bd;
    if (bd->isEnum) {
        auto en = dynamic_cast<EnumDecl *>(bd);
        for (auto ev : en->variants) {
            for (auto ep : ev->fields) {
                ep->type->accept(this);
            }
        }
    } else {
        auto td = dynamic_cast<TypeDecl *>(bd);
        for (auto fd : td->fields) {
            fd->accept(this);
            curScope()->add(new VarHolder(fd));
        }
    }
    curDecl = nullptr;
    return typeMap[bd->name];
}

void *Resolver::visitFieldDecl(FieldDecl *fd) {
    auto id = fd->parent->name + "#" + fd->name;
    auto it = cache.find(id);
    //if(it!=cache.end()) return it->second;
    auto res = clone((RType *) fd->type->accept(this));
    res->vh = new VarHolder(fd);
    //res->targetDecl = fd->parent;
    cache[id] = res;
    //if(fd->expr) fd->expr->accept (this);
    return res;
}

void *Resolver::visitMethod(Method *m) {
    if (!m->typeArgs.empty()) {
        error("generic method");
    }
    auto it = methodMap.find(m);
    if (it != methodMap.end()) return it->second;
    curMethod = m;
    auto res = clone((RType *) m->type->accept(this));
    res->targetMethod = m;
    newScope();
    methodScopes[m] = curScope();
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

void *Resolver::visitParam(Param *p) {
    auto res = clone(resolveType(p->type.get()));
    paramMap[p] = res;
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
    if (!res) res = rhs;
    res->targetVar = f;
    varMap[f] = res;
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
    if (decl->isEnum) {
        throw std::runtime_error("enum template");
    } else {
        auto res = new TypeDecl;
        res->isEnum = false;
        res->name = decl->name;
        for (auto ta : type->typeArgs) {
            res->name += "_" + ta->print();
        }
        auto td = dynamic_cast<TypeDecl *>(decl);
        auto gen = new Generator(type->typeArgs, decl->typeArgs);
        // for (auto ta : type->typeArgs) {
        //     res->typeArgs.push_back((Type *) ta->accept(gen));
        // }
        for (auto fd : td->fields) {
            auto type = (Type *) fd->type->accept(gen);
            auto field = new FieldDecl(fd->name, type, res);
            res->fields.push_back(field);
        }
        for (auto m : td->methods) {
            auto method = (Method *) gen->visitMethod(m);
            method->parent = res;
            method->typeArgs.clear();
            res->methods.push_back(method);
        }
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
        res = new RType;
        res->type = type;
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
    if (type->scope == nullptr) {
        for (auto bd : unit->types) {
            if (bd->name != type->name) {
                continue;
            }
            checkTypeArgs(type->typeArgs, bd->typeArgs);
            if (!bd->typeArgs.empty()) {
                auto decl = generateDecl(type, bd);
                // for (auto m : decl->methods) {
                //     genericMethodsTodo.push_back(m);
                // }
                res = new RType;
                res->type = simpleType(type->name);
                for (auto ta : type->typeArgs) {
                    res->type->typeArgs.push_back(copy(ta));
                }
                res->targetDecl = decl;
                genericTypes.push_back(decl);
                typeMap[str] = res;
                return res;
            } else {
                return (RType *) visitBaseDecl(bd);
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
    if (bd->isEnum) {
        auto ed = dynamic_cast<EnumDecl *>(bd);
        findVariant(ed, type->name);
        res = (RType *) visitBaseDecl(ed);
    }
    if (!res) throw std::runtime_error("todo resolveType: " + str);
    typeMap[str] = res;
    return res;
}

void *Resolver::visitAssign(Assign *as) {
    auto t1 = resolve(as->left);
    auto t2 = resolve(as->right);
    if (!subType(t2->type, t1->type)) {
        error("cannot assign " + as->right->print() + " to " + as->left->print());
    }
    // return t1 because t2 is going to be autocast to t1 ultimately
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
        if (!res->type->isIntegral()) {
            error("unary on non prim: " + u->print());
        }
        if (u->op == "--" || u->op == "++") {
            if (!iof<Name *>(u->expr) && !iof<FieldAccess *>(u->expr)) {
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
            if (curMethod && curMethod->isStatic && std::get_if<FieldDecl *>(vh)) {
                continue;
            }
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
        dump();
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
    } else if (decl->isEnum) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        if (fa->name != "index") {
            throw std::runtime_error("invalid field " + fa->name + " in " +
                                     scp->type->print());
        }
        res = makeSimple("int");
    } else {
        auto td = dynamic_cast<TypeDecl *>(decl);
        int i = fieldIndex(td, fa->name);
        auto fd = td->fields[i];
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

void *Resolver::visitArrayCreation(ArrayCreation *ac) {
    for (auto &e : ac->dims) {
        e->accept(this);
    }
    return ac->type->accept(this);
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
    if (!iof<Name *>(e->expr)) {
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
    if (!rt->targetDecl->isEnum) {
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
    if (!rhs->targetDecl->isEnum) {
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

void *Resolver::visitExprStmt(ExprStmt *st) {
    if (!iof<MethodCall *>(st->expr) && !iof<Assign *>(st->expr) && !iof<Unary *>(st->expr) && !iof<Postfix *>(st->expr)) {
        error("invalid expr statement: " + st->print());
    }
    st->expr->accept(this);
    return nullptr;
}

void *Resolver::visitBlock(Block *st) {
    for (auto& st : st->list) {
        st->accept(this);
    }
    return nullptr;
}

void *Resolver::visitIfStmt(IfStmt *st) {
    if (!isCondition(st->expr.get(), this)) {
        error("if condition is not a boolean");
    }
    st->thenStmt->accept(this);
    if (st->elseStmt) st->elseStmt->accept(this);
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
    if (!decl1->isEnum) {
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
    if (res->targetDecl->isEnum) {
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
        auto td = dynamic_cast<TypeDecl *>(res->targetDecl);
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
            auto prm = td->fields[i];
            auto vt = resolve(prm->type);
            auto val = resolve(e.value);
            if (!subType(val->type, prm->type)) {
                error("variant field type is imcompatiple with " + e.value->print());
            }
        }
        if (hasNamed) {
            for (auto p : td->fields) {
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
    if (!arr->type->isPointer()) error("array expr is not a pointer: " + node->print());
    auto idx = resolve(node->index);
    //todo unsigned
    if (!idx->type->isIntegral()) error("array index is not an integer");
    auto ptr = dynamic_cast<PointerType *>(arr->type);
    return resolveType(ptr->type);
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

RType *scopedMethod(MethodCall *mc, Resolver *r) {
    auto scope = r->resolve(mc->scope.get());
    if (dynamic_cast<Type *>(mc->scope.get())) {
        //static method
        std::vector<Method *> list;
        for (auto m : scope->targetDecl->methods) {
            if (!m->isStatic) continue;
            if (m->name == mc->name) {
                list.push_back(m);
            }
        }
        if (list.empty()) {
            error("no such method: " + mc->name);
        }
        if (list.size() > 1) error("more than 1 candidate");
        auto target = list[0];
        auto res = r->resolveType(target->type.get());
        res->targetMethod = target;
        r->usedMethods.push_back(target);
        return res;
    } else {
        //member method
        std::vector<Method *> list;
        for (auto m : scope->targetDecl->methods) {
            if (m->isStatic) continue;
            if (m->name == mc->name) {
                list.push_back(m);
            }
        }
        if (list.empty()) {
            error("no such method: " + mc->name);
        }
        if (list.size() > 1) error("more than 1 candidate");
        auto target = list[0];
        auto res = r->resolveType(target->type.get());
        res->targetMethod = target;
        r->usedMethods.push_back(target);
        return res;
    }
    throw std::runtime_error("scopedMethod");
}


void findMethod(Unit *unit, MethodCall *mc, std::vector<Method *> &list) {
    for (auto m : unit->methods) {
        if (m->name == mc->name) {
            list.push_back(m);
        }
    }
}

void *Resolver::visitMethodCall(MethodCall *mc) {
    auto id = getId(mc);
    auto it = cache.find(id);
    if (it != cache.end()) return it->second;
    for (auto arg : mc->args) {
        resolve(arg);
    }
    if (mc->scope) {
        return scopedMethod(mc, this);
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
    }
    std::vector<Method *> cand;// candidates
    for (auto m : unit->methods) {
        if (m->name == mc->name) {
            cand.push_back(m);
        }
    }
    if (curDecl) {
        //static sibling method
        for (auto m : curDecl->methods) {
            if (m->name == mc->name) {
                cand.push_back(m);
            }
        }
    }
    for (auto is : unit->imports) {
        auto resolver = getResolver(root + "/" + join(is->list, "/") + ".x", root);
        resolver->resolveAll();
        try {
            findMethod(resolver->unit.get(), mc, cand);
        } catch (std::exception &e) {
        }
    }
    if (cand.empty()) {
        throw std::runtime_error("method:  " + mc->name + " not found");
    }

    //filter
    std::vector<Method *> real;
    for (auto c : cand) {
        if (isSame(this, mc, c)) {
            real.push_back(c);
        }
    }
    if (real.empty()) {
        //print cand
        throw std::runtime_error("method: " + mc->name + " not found from candidates: ");
    }
    if (real.size() > 1) {
        throw std::runtime_error("method:  " + mc->name + " has " +
                                 std::to_string(cand.size()) + " candidates");
    }
    auto trg = real[0];
    RType *res;
    if (!trg->typeArgs.empty()) {
        auto newMethod = generateMethod(mc->typeArgs, trg);
        res = clone(resolveType(newMethod->type.get()));
        res->targetMethod = newMethod;
        genericMethodsTodo.push_back(newMethod);
    } else {
        res = clone(resolveType(trg->type.get()));
        res->targetMethod = trg;
        if (trg->unit != unit.get()) {
            usedMethods.push_back(trg);
        }
    }
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