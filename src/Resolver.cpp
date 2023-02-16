#include "Resolver.h"
#include "MethodResolver.h"
#include "TypeUtils.h"
#include "parser/Parser.h"
#include "parser/Util.h"
#include <any>
#include <list>
#include <memory>
#include <unordered_set>


bool isCondition(Expression *e, Resolver *r) {
    return r->resolve(e).type->print() == "bool";
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

RType clone(const RType &rt) {
    auto res = RType(clone(rt.type));
    res.unit = rt.unit;
    res.targetDecl = rt.targetDecl;
    res.targetMethod = rt.targetMethod;
    return res;
}

Type *copy(Type *arg) {
    AstCopier copier;
    return (Type *) std::any_cast<Expression *>(arg->accept(&copier));
}

RType makeSimple(const std::string &name) {
    return RType(new Type(name));
}

RType binCast(const std::string &t1, const std::string &t2) {
    if (t1 == t2) {
        return makeSimple(t1);
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
    auto unit = parser.parseUnit();
    auto resolver = std::make_shared<Resolver>(unit, root);
    resolverMap[path] = resolver;
    return resolver;
}

//replace any type in decl with src by same index
std::any Generator::visitType(Type *type) {
    type = (Type *) std::any_cast<Expression *>(AstCopier::visitType(type));
    if (type->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(type);
        ptr->type = (Type *) std::any_cast<Expression *>(ptr->type->accept(this));
        return (Expression *) ptr;
    }
    for (auto &ta : type->typeArgs) {
        ta = (Type *) std::any_cast<Expression *>(ta->accept(this));
    }
    auto str = type->print();
    auto it = map.find(str);
    if (it != map.end()) {
        return std::any_cast<Expression *>(AstCopier::visitType(it->second));
    }
    return (Expression *) type;
}

int Resolver::findVariant(EnumDecl *decl, const std::string &name) {
    for (int i = 0; i < decl->variants.size(); i++) {
        if (decl->variants[i]->name == name) {
            return i;
        }
    }
    throw std::runtime_error("unknown variant: " + name + " of type " + decl->type->print());
}

std::string nameOf(const VarHolder *vh) {
    auto f = std::get_if<Fragment *>(vh);
    if (f) return (*f)->name;
    auto p = std::get_if<Param *>(vh);
    if (p) return (*p)->name;
    auto fd = std::get_if<FieldDecl *>(vh);
    if (fd) return (*fd)->name;
    auto ep = std::get_if<EnumPrm *>(vh);
    return (*ep)->name;
}

void Scope::add(const VarHolder &f) {
    for (auto &prev : list) {
        if (nameOf(&prev) == nameOf(&f)) {
            throw std::runtime_error("variable " + nameOf(&f) + " already declared in the same scope");
        }
    }
    list.push_back(f);
}

void Scope::clear() { list.clear(); }


std::optional<VarHolder> Scope::find(const std::string &name) {
    for (auto &vh : list) {
        if (nameOf(&vh) == name) {
            return vh;
        }
    }
    return std::nullopt;
}

std::string Resolver::getId(Expression *e) {
    auto res = e->accept(idgen);
    if (res.has_value()) {
        return std::any_cast<std::string>(res);
    }
    throw std::runtime_error("id: " + e->print());
}

std::unordered_map<std::string, std::shared_ptr<Resolver>> Resolver::resolverMap;

Resolver::Resolver(std::shared_ptr<Unit> unit, const std::string &root) : unit(unit), root(root) {
    idgen = new IdGen(this);
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
    int i = 0, j = 0;
    while (true) {
        for (; i < genericTypes.size(); i++) {
            auto gt = genericTypes[i];
            gt->accept(this);
        }
        //todo dont visit used type methods they already visited
        int old = genericTypes.size();
        for (; j < usedTypes.size(); j++) {
            auto gt = usedTypes[j];
            gt->accept(this);
        }
        if (old == genericTypes.size()) break;
    }

    for (int i = 0; i < generatedMethods.size(); i++) {
        auto gm = generatedMethods[i];
        if (gm->parent) {
            curImpl = dynamic_cast<Impl *>(gm->parent);
        }
        gm->accept(this);
        curImpl = nullptr;
    }
}

void Resolver::init() {
    for (auto &item : unit->items) {
        if (item->isImpl()) {
            auto impl = dynamic_cast<Impl *>(item.get());
            if (impl->type->typeArgs.empty()) {
                continue;
            }
            //copy impl type params into all methods
            for (auto &m : impl->methods) {
                m->isGeneric = true;
                for (auto &ta : impl->type->typeArgs) {
                    m->typeArgs.push_back(ta);
                }
            }
        }
        if (!item->isClass() && !item->isEnum()) {
            continue;
        }
        auto bd = dynamic_cast<BaseDecl *>(item.get());
        auto res = makeSimple(bd->getName());
        res.unit = unit;
        res.targetDecl = bd;
        addType(bd->getName(), res);
    }
}

RType Resolver::resolve(Expression *expr) {
    auto idtmp = expr->accept(idgen);
    if (!idtmp.has_value()) {
        return std::any_cast<RType>(expr->accept(this));
    }
    auto id = std::any_cast<std::string>(idtmp);
    auto it = cache.find(id);
    if (it != cache.end()) return it->second;
    auto res = std::any_cast<RType>(expr->accept(this));
    cache[id] = res;
    return res;
}
Type *Resolver::getType(Expression *expr) {
    return resolve(expr).type;
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
    auto bd = resolve(type).targetDecl;
    if (bd->isEnum()) {
        auto en = dynamic_cast<EnumDecl *>(bd);
        for (auto ev : en->variants) {
            for (auto &f : ev->fields) {
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
std::any Resolver::visitEnumDecl(EnumDecl *node) {
    if (node->isGeneric) {
        return nullptr;
    }
    if (node->isResolved) {
        error("already resolved");
    }
    node->isResolved = true;
    for (auto ev : node->variants) {
        for (auto &ep : ev->fields) {
            resolve(ep->type);
        }
    }
    curDecl = nullptr;
    return getTypeCached(node->getName());
}

RType Resolver::getTypeCached(const std::string &name) {
    auto it = typeMap.find(name);
    if (it != typeMap.end()) {
        return it->second;
    }
    return {};
}

void Resolver::addType(const std::string &name, const RType &rt) {
    typeMap[name] = rt;
}

std::any Resolver::visitStructDecl(StructDecl *node) {
    if (node->isGeneric) {
        return nullptr;
    }
    if (node->isResolved) {
        //error("already resolved");
        return getTypeCached(node->getName());
    }
    node->isResolved = true;
    curDecl = node;
    for (auto &fd : node->fields) {
        fd->accept(this);
    }
    curDecl = nullptr;
    return getTypeCached(node->getName());
}

std::any Resolver::visitImpl(Impl *node) {
    if (!node->type->typeArgs.empty()) return nullptr;
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

std::any Resolver::visitTrait(Trait *node) {
    //todo
    return nullptr;
}

std::any Resolver::visitExtern(Extern *node){
    for (auto &m : node->methods) {
        if (!m->typeArgs.empty()) {
            continue;
        }
        m->accept(this);
    }
    return nullptr;
}

std::any Resolver::visitFieldDecl(FieldDecl *node) {
    auto res = clone(resolve(node->type));
    res.vh = VarHolder(node);
    return res;
}

std::any Resolver::visitMethod(Method *m) {
    if (m->isGeneric) {
        return nullptr;
    }
    auto it = methodMap.find(m);
    if (it != methodMap.end()) return it->second;
    curMethod = m;
    auto res = clone(resolve(m->type.get()));
    res.targetMethod = m;
    newScope();
    methodScopes[m] = curScope();
    if (m->self) {
        curScope()->add(VarHolder(m->self.get()));
        m->self->accept(this);
    }
    for (auto &prm : m->params) {
        curScope()->add(VarHolder(prm.get()));
        prm->accept(this);
    }
    if (m->body) {
        m->body->accept(this);
        //todo check unreachable
        if (!m->type->isVoid() && !isReturnLast(m->body.get())) {
            error("non void function must return a value");
        }
    }
    dropScope();
    methodMap[m] = res;
    curMethod = nullptr;
    return res;
}

std::any Resolver::visitParam(Param *p) {
    auto id = printMethod(p->method) + "#" + p->name;
    if (paramMap.find(id) != paramMap.end()) return paramMap[id];
    auto res = clone(resolve(p->type.get()));
    paramMap[id] = res;
    return res;
}

std::any Resolver::visitFragment(Fragment *f) {
    auto it = varMap.find(f);
    if (it != varMap.end()) return it->second;
    RType res;
    if (f->type) {
        res = resolve(f->type.get());
    }
    auto rhs = resolve(f->rhs.get());
    if (f->type && !MethodResolver::isCompatible(rhs.type, res.type)) {
        std::string msg = "variable type mismatch '" + f->name + "'\n";
        msg += "expected: " + res.type->print() + " got " + rhs.type->print();
        error(msg);
    }
    if (!f->type) res = clone(rhs);
    varMap[f] = res;
    //todo visit once
    curScope()->add(VarHolder(f));
    return res;
}

std::any Resolver::visitVarDeclExpr(VarDeclExpr *vd) {
    for (auto *f : vd->list) {
        f->accept(this);
    }
    return nullptr;
}

std::any Resolver::visitVarDecl(VarDecl *vd) {
    visitVarDeclExpr(vd->decl);
    return nullptr;
}

BaseDecl *generateDecl(Type *type, BaseDecl *decl) {
    std::map<std::string, Type *> map;
    for (int i = 0; i < decl->type->typeArgs.size(); i++) {
        auto ta = decl->type->typeArgs[i];
        map[ta->name] = type->typeArgs[i];
    }
    auto gen = new Generator(map);
    if (decl->isEnum()) {
        auto res = new EnumDecl;
        res->unit = decl->unit;
        res->type = clone(type);
        auto ed = dynamic_cast<EnumDecl *>(decl);
        for (auto ev : ed->variants) {
            auto ev2 = new EnumVariant;
            ev2->name = ev->name;
            for (auto &field : ev->fields) {
                auto ftype = (Type *) std::any_cast<Expression *>(field->type->accept(gen));
                auto field2 = new FieldDecl(field->name, ftype);
                ev2->fields.push_back(std::unique_ptr<FieldDecl>(field2));
            }
            res->variants.push_back(ev2);
        }
        return res;
    } else {
        auto res = new StructDecl;
        res->unit = decl->unit;
        res->type = clone(type);
        auto td = dynamic_cast<StructDecl *>(decl);

        for (auto &field : td->fields) {
            auto ftype = (Type *) std::any_cast<Expression *>(field->type->accept(gen));
            auto field2 = new FieldDecl(field->name, ftype);
            res->fields.push_back(std::unique_ptr<FieldDecl>(field2));
        }
        return res;
    }
}

std::any Resolver::visitType(Type *type) {
    auto str = type->print();
    auto it = typeMap.find(str);
    if (it != typeMap.end()) {
        return it->second;
    }
    if (type->isPrim() || type->isVoid()) {
        if (isUnsigned(str)) {
            error("unsigned types not yet supported");
        }
        auto res = RType(type);
        typeMap[str] = res;
        return res;
    }
    if (type->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(type);
        auto res = clone(resolve(ptr->type));
        auto inner = res.type;
        res.type = new PointerType(inner);
        typeMap[str] = res;
        return res;
    }
    if (type->isSlice()) {
        auto slice = dynamic_cast<SliceType *>(type);
        auto inner = clone(resolve(slice->type));
        auto res = RType(new SliceType(inner.type));
        typeMap[str] = res;
        return res;
    }
    if (type->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(type);
        auto inner = clone(resolve(arr->type));
        auto res = RType(new ArrayType(inner.type, arr->size));
        typeMap[str] = res;
        return res;
    }
    if (type->scope) {
        auto scope = resolve(type->scope.get());
        auto bd = scope.targetDecl;
        if (!bd->isEnum()) {
            throw std::runtime_error("couldn't find type: " + str);
        }
        //enum variant creation
        auto ed = dynamic_cast<EnumDecl *>(bd);
        findVariant(ed, type->name);
        auto res = getTypeCached(ed->type->print());
        addType(str, res);
        return res;
    }else if(curImpl){
        auto r = resolve(curImpl->type);
        if(r.targetDecl && r.targetDecl->isEnum()){
            auto ed = (EnumDecl*)r.targetDecl;
          for(auto v:ed->variants){
              if(v->name==type->name){
                  //enum variant without scope(same impl)
                  auto res = getTypeCached(ed->type->print());
                  addType(str, res);
                  return res;
              }
          }
        }
    }
    
    if (str == "Self") {
        if (curMethod->parent) {
            auto imp = dynamic_cast<Impl *>(curMethod->parent);
            return resolve(imp->type);
        }
    }
    BaseDecl *target = nullptr;
    if (!type->typeArgs.empty()) {
        //we looking for generic type
        auto it = typeMap.find(type->name);
        if (it != typeMap.end()) {
            target = it->second.targetDecl;
        } else {
            //generic from imports
        }
    }
    if (!target) {
        for (auto is : unit->imports) {
            auto resolver = getResolver(root + "/" + join(is->list, "/") + ".x", root);
            resolver->resolveAll();
            //try full type
            if (type->typeArgs.empty()) {
                //non generic type
                auto it = resolver->typeMap.find(str);
                if (it != resolver->typeMap.end()) {
                    auto res = it->second;
                    addType(str, res);
                    usedTypes.push_back(res.targetDecl);
                    return res;
                }
            } else {
                //generic type
                //try root type
                auto it = resolver->typeMap.find(type->name);
                if (it != resolver->typeMap.end()) {
                    target = it->second.targetDecl;
                    break;
                }
            }
        }
    }
    if (!target) {
        throw std::runtime_error("couldn't find type: " + str);
    }
    //generic
    if (type->typeArgs.empty()) {
        //inferred later
        auto res = RType(clone(target->type));
        res.targetDecl = target;
        addType(str, res);
        return res;
    }
    if (type->typeArgs.size() != target->type->typeArgs.size()) {
        error("type arguments size not matched");
    }
    auto decl = generateDecl(type, target);
    auto res = RType(new Type(type->name));
    for (auto ta : type->typeArgs) {
        res.type->typeArgs.push_back(copy(ta));
    }
    res.targetDecl = decl;
    genericTypes.push_back(decl);
    addType(str, res);
    return res;
}

//todo field mutation doesn't need alloc
Param *isMut(Expression *e, Resolver *r) {
    auto sn = dynamic_cast<SimpleName *>(e);
    if (sn) {
        auto rt = r->resolve(sn);
        if (std::get_if<Param *>(&rt.vh.value()) && isStruct(rt.type)) {
            return *std::get_if<Param *>(&rt.vh.value());
        }
        return nullptr;
    }
    auto aa = dynamic_cast<ArrayAccess *>(e);
    if (aa) {
        return isMut(aa->array, r);
    }
    auto de = dynamic_cast<DerefExpr *>(e);
    if (de) {
        return isMut(de->expr.get(), r);
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

std::any Resolver::visitAssign(Assign *node) {
    auto t1 = resolve(node->left);
    auto t2 = resolve(node->right);
    if (!subType(t2.type, t1.type)) {
        error("cannot assign " + node->right->print() + " to " + node->left->print());
    }
    auto prm = isMut(node->left, this);
    if (prm) {
        mut_params.insert(prm);
    }
    return t1;
}

std::any Resolver::visitInfix(Infix *node) {
    auto rt1 = resolve(node->left);
    auto rt2 = resolve(node->right);
    if (rt1.type->isVoid() || rt2.type->isVoid()) {
        error("operation on void type");
    }
    if (rt1.type->isString() || rt2.type->isString()) {
        error("string op not supported yet");
    }
    if (!rt1.type->isPrim() || !rt2.type->isPrim()) {
        error("infix on non prim type: " + node->print());
    }

    RType res;
    if (isComp(node->op)) {
        res = makeSimple("bool");
    } else if (node->op == "&&" || node->op == "||") {
        if (rt1.type->print() != "bool") {
            error("infix lhs is not boolean: " + node->left->print());
        }
        if (rt2.type->print() != "bool") {
            error("infix rhs is not boolean: " + node->right->print());
        }
        res = makeSimple("bool");
    } else {
        auto s1 = rt1.type->print();
        auto s2 = rt2.type->print();
        res = binCast(s1, s2);
    }
    return res;
}

std::any Resolver::visitUnary(Unary *node) {
    //todo check unsigned
    auto res = resolve(node->expr);
    if (node->op == "!") {
        if (res.type->print() != "bool") {
            error("unary on non boolean: " + node->print());
        }
    } else {
        if (res.type->print() == "bool" || !res.type->isPrim()) {
            error("unary on non interal: " + node->print());
        }
        if (node->op == "--" || node->op == "++") {
            if (!iof<SimpleName *>(node->expr) && !iof<FieldAccess *>(node->expr)) {
                error("prefix on non variable: " + node->print());
            }
        }
    }
    return res;
}

std::vector<Symbol> Resolver::find(std::string &name, bool checkOthers) {
    std::vector<Symbol> res;
    //params+locals
    for (int i = scopes.size() - 1; i >= 0; i--) {
        auto vh = scopes[i]->find(name);
        if (vh) {
            res.push_back(Symbol(vh.value(), this));
        }
    }
    return res;
}
std::any Resolver::visitSimpleName(SimpleName *node) {
    auto id = getId(node);
    auto it = cache.find(id);
    if (it != cache.end()) return it->second;

    auto arr = find(node->name, true);
    if (arr.empty()) {
        throw std::runtime_error("unknown identifier: " + node->name);
    }
    if (arr.size() > 1) {
        throw std::string("more than 1 result for ") + node->name;
    }
    RType res;
    auto s = arr[0];
    if (s.v) {
        auto vh = &s.v.value();
        auto frag = std::get_if<Fragment *>(vh);
        if (frag) {
            res = s.resolve(*frag);
        }
        auto prm = std::get_if<Param *>(vh);
        if (prm) {
            res = s.resolve(*prm);
        }
        auto field = std::get_if<FieldDecl *>(vh);
        if (field) {
            res = s.resolve(*field);
        }
        auto ep = std::get_if<EnumPrm *>(vh);
        if (ep) {
            res = s.resolve((*ep)->decl->type);
        }
        res = clone(res);
        res.vh = s.v;
    } else if (s.m) {
        res = s.resolve(s.m);
    } else if (s.decl) {
        res = s.resolve(s.decl);
    } else {
        throw std::runtime_error("unexpected state");
    }
    cache[id] = res;
    return res;
}

std::any Resolver::visitFieldAccess(FieldAccess *node) {
    auto scp = resolve(node->scope);
    if (scp.type->isString()) {
        scp = resolve(scp.type);
    }
    auto decl = scp.targetDecl;
    if (scp.type->isSlice()) {
        if (node->name != "len") {
            throw std::runtime_error("invalid field " + node->name + " in " +
                                     scp.type->print());
        }
        return makeSimple("i32");
    } else if (decl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        if (node->name != "index") {
            throw std::runtime_error("invalid field " + node->name + " in " +
                                     scp.type->print());
        }
        return makeSimple("i32");
    } else {
        auto td = dynamic_cast<StructDecl *>(decl);
        int i = fieldIndex(td->fields, node->name, td->type);
        auto &fd = td->fields[i];
        return std::any_cast<RType>(fd->accept(this));
    }
}

std::any Resolver::visitLiteral(Literal *node) {
    if (node->suffix) {
        return RType(node->suffix.get());
    }
    std::string name;
    auto type = node->type;
    if (type == Literal::STR) {
        name = "str";
    } else if (type == Literal::BOOL) {
        name = "bool";
    } else if (type == Literal::FLOAT) {
        name = "f32";
    } else if (type == Literal::INT) {
        name = "i32";
    } else if (type == Literal::CHAR) {
        name = "i32";
    } else {
        throw std::runtime_error("unknown literal: " + node->print());
    }
    //todo check max value
    return RType(new Type(name));
}

std::any Resolver::visitAsExpr(AsExpr *node) {
    auto left = resolve(node->expr);
    auto right = resolve(node->type);
    //prim->prim
    if (!left.type->isPrim() || left.type->isVoid()) {
        error("as expr must be primitive: " + node->expr->print());
    }
    if (!right.type->isPrim() || right.type->isVoid()) {
        error("as type must be primitive: " + node->type->print());
    }
    return right;
}

std::any Resolver::visitRefExpr(RefExpr *node) {
    //todo field access
    if (!iof<SimpleName *>(node->expr.get()) && !iof<ArrayAccess *>(node->expr.get())) {
        error("ref expr is not supported: " + node->expr->print());
    }
    auto inner = clone(resolve(node->expr.get()));
    inner.type = new PointerType(inner.type);
    return inner;
}

std::any Resolver::visitDerefExpr(DerefExpr *node) {
    auto res = clone(resolve(node->expr.get()));
    auto inner = res.type;
    if (!inner->isPointer()) {
        error("deref expr is not pointer: " + node->expr->print());
    }
    auto ptr = dynamic_cast<PointerType *>(inner);
    res.type = ptr->type;
    return res;
}

std::any Resolver::visitAssertStmt(AssertStmt *node) {
    if (!isCondition(node->expr.get(), this)) {
        error("assert expr is not boolean expr: " + node->expr->print());
    }
    return nullptr;
}

std::any Resolver::visitIfLetStmt(IfLetStmt *node) {
    newScope();
    auto rt = resolve(node->type.get());
    if (!rt.targetDecl->isEnum()) {
        error("type of if let is not enum: " + node->type->print());
    }
    auto decl = dynamic_cast<EnumDecl *>(rt.targetDecl);
    int index = findVariant(decl, node->type->name);
    auto variant = decl->variants[index];
    int i = 0;
    for (auto &name : node->args) {
        auto tmp = new EnumPrm;
        tmp->decl = variant->fields[i].get();
        tmp->name = name;
        curScope()->add(VarHolder(tmp));
        i++;
    }
    auto rhs = resolve(node->rhs.get());
    if (!rhs.targetDecl->isEnum()) {
        error("if let rhs is not enum: " + node->rhs->print());
    }
    node->thenStmt->accept(this);
    dropScope();
    if (node->elseStmt) {
        node->elseStmt->accept(this);
    }
    return nullptr;
}

std::any Resolver::visitParExpr(ParExpr *node) {
    return node->expr->accept(this);
}

std::any Resolver::visitExprStmt(ExprStmt *node) {
    if (!iof<MethodCall *>(node->expr) && !iof<Assign *>(node->expr) && !iof<Unary *>(node->expr) && !iof<Postfix *>(node->expr)) {
        error("invalid expr statement: " + node->print());
    }
    node->expr->accept(this);
    return nullptr;
}

std::any Resolver::visitBlock(Block *node) {
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

std::any Resolver::visitIfStmt(IfStmt *node) {
    if (!isCondition(node->expr.get(), this)) {
        error("if condition is not a boolean");
    }
    node->thenStmt->accept(this);
    if (node->elseStmt) {
        node->elseStmt->accept(this);
    }
    return nullptr;
}

std::any Resolver::visitReturnStmt(ReturnStmt *node) {
    if (node->expr) {
        if (curMethod->type->isVoid()) {
            error("void method returns expr");
        }
        auto type = resolve(node->expr.get()).type;
        auto mtype = resolve(curMethod->type.get()).type;
        if (!subType(type, mtype)) {
            error("method " + printMethod(curMethod) + " expects '" + mtype->print() + " but returned '" + type->print() + "'");
        }
    } else {
        if (!curMethod->type->isVoid()) {
            error("non-void method returns void");
        }
    }
    return nullptr;
}

std::any Resolver::visitIsExpr(IsExpr *node) {
    auto rt = resolve(node->expr);
    auto decl1 = rt.targetDecl;
    if (!decl1->isEnum()) {
        error("lhs of is expr is not enum");
    }
    auto rt2 = resolve(node->type->scope.get());
    auto decl2 = rt2.targetDecl;
    if (decl1 != decl2) {
        error("rhs of is expr is not enum");
    }
    findVariant(dynamic_cast<EnumDecl *>(decl1), node->type->name);
    return makeSimple("bool");
}

Type *Resolver::inferStruct(ObjExpr *node, bool hasNamed, std::vector<Type *> &typeArgs, std::vector<std::unique_ptr<FieldDecl>> &fields, Type *type) {
    std::map<std::string, Type *> inferMap;
    for (auto ta : typeArgs) {
        inferMap[ta->name] = nullptr;
    }
    for (int i = 0; i < node->entries.size(); i++) {
        auto &e = node->entries[i];
        int prm_idx;
        if (hasNamed) {
            prm_idx = fieldIndex(fields, e.key, type);
        } else {
            prm_idx = i;
        }
        auto arg_type = resolve(e.value);
        auto target_type = fields[i]->type;

        MethodResolver::infer(arg_type.type, target_type, inferMap);
    }
    for (auto &i : inferMap) {
        if (i.second == nullptr) {
            error("can't infer type parameter: " + i.first);
        }
    }
    auto res = new Type(type->name);
    for (auto &e : inferMap) {
        res->typeArgs.push_back(e.second);
    }
    return res;
}

std::any Resolver::visitObjExpr(ObjExpr *node) {
    bool hasNamed = false;
    bool hasNonNamed = false;
    for (auto &e : node->entries) {
        if (e.hasKey()) {
            hasNamed = true;
        } else {
            hasNonNamed = true;
        }
    }
    if (hasNamed && hasNonNamed) {
        throw std::runtime_error("obj creation can't have mixed values");
    }
    auto res = resolve(node->type.get());
    if (node->isPointer) {
        res = clone(res);
        res.type = new PointerType(res.type);
    }
    std::unordered_set<std::string> names;
    std::vector<std::unique_ptr<FieldDecl>> *fields;
    Type *type;
    if (res.targetDecl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(res.targetDecl);
        int idx = findVariant(ed, node->type->name);
        auto variant = ed->variants[idx];
        fields = &variant->fields;
        type = new Type(ed->type, variant->name);
        if (variant->fields.size() != node->entries.size()) {
            error("incorrect number of arguments passed to enum creation");
        }
    } else {
        auto td = dynamic_cast<StructDecl *>(res.targetDecl);
        fields = &td->fields;
        type = td->type;
        if (td->fields.size() != node->entries.size()) {
            error("incorrect number of arguments passed to class creation");
        }
        if (td->isGeneric) {
            //infer
            auto inferred = inferStruct(node, hasNamed, td->type->typeArgs, td->fields, td->type);
            auto decl = generateDecl(inferred, td);
            td = dynamic_cast<StructDecl *>(decl);
            genericTypes.push_back(decl);
            res = resolve(decl->type);
            fields = &td->fields;
        }
    }
    for (int i = 0; i < node->entries.size(); i++) {
        auto &e = node->entries[i];
        int prm_idx;
        if (hasNamed) {
            names.insert(e.key);
            prm_idx = fieldIndex(*fields, e.key, type);
        } else {
            prm_idx = i;
        }
        auto &prm = fields->at(i);
        auto vt = resolve(prm->type);
        auto val = resolve(e.value);
        if (!subType(val.type, prm->type)) {
            error("variant field type is imcompatiple with " + e.value->print() + " expected " + prm->type->print());
        }
    }
    if (hasNamed) {
        for (auto &p : *fields) {
            if (names.find(p->name) == names.end()) {
                error("field not covered: " + p->name);
            }
        }
    }
    return res;
}

std::any Resolver::visitArrayAccess(ArrayAccess *node) {
    auto arr = resolve(node->array).type;
    auto idx = resolve(node->index).type;
    //todo unsigned
    if (idx->print() == "bool" || !idx->isPrim()) error("array index is not an integer");
    if (node->index2) {
        auto idx2 = resolve(node->index2.get()).type;
        if (idx2->print() == "bool" || !idx2->isPrim()) error("range end is not an integer");
        if (arr->isSlice()) {
            auto st = dynamic_cast<SliceType *>(arr);
            return RType(st);
        } else if (arr->isArray()) {
            auto at = dynamic_cast<ArrayType *>(arr);
            return RType(new SliceType(at->type));
        } else if (arr->isPointer()) {
            auto pt = dynamic_cast<PointerType *>(arr);
            return RType(new SliceType(pt->type));
        } else {
            error("can't make slice out of " + arr->print());
        }
    }
    if (arr->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(arr);
        auto res = resolve(ptr->type);
        if (res.type->isArray() || res.type->isSlice()) {
            arr = res.type;
        } else {
            return res;
        }
    }
    if (arr->isArray()) {
        auto at = dynamic_cast<ArrayType *>(arr);
        return resolve(at->type);
    }
    if (arr->isSlice()) {
        auto at = dynamic_cast<SliceType *>(arr);
        return resolve(at->type);
    }
    throw std::runtime_error("array expr is not a pointer: " + node->print());
}

std::any Resolver::visitMethodCall(MethodCall *mc) {
    auto id = getId(mc);
    auto it = cache.find(id);
    if (it != cache.end()) return it->second;
    auto sig = Signature::make(mc, this);
    if (mc->scope) {
        MethodResolver mr(this);
        auto list=mr.collect(sig);
        auto res = handleCallResult(list, &sig);
        cache[id] = res;
        return res;
    }
    if (mc->name == "print") {
        return makeSimple("void");
    } else if (mc->name == "malloc") {
        Type *in;
        if (mc->typeArgs.empty()) {
            in = new Type("i8");
        } else {
            in = getType(mc->typeArgs[0]);
        }
        return RType(new PointerType(in));
    } else if (mc->name == "panic") {
        if (mc->args.empty()) {
            return RType(new Type("void"));
        }
        auto lit = dynamic_cast<Literal *>(mc->args[0]);
        if (lit && lit->type == Literal::STR) {
            return RType(new Type("void"));
        }
        throw std::runtime_error("invalid panic argument: " + mc->args[0]->print());
    }
    
    MethodResolver mr(this);
    auto list=mr.collect(sig);
    auto res = handleCallResult(list, &sig);
    cache[id] = res;
    return res;
}

std::any Resolver::visitWhileStmt(WhileStmt *node) {
    if (!isCondition(node->expr.get(), this)) {
        error("while statement expr is not a bool");
    }
    inLoop = true;
    node->body->accept(this);
    inLoop = false;
    return nullptr;
}

std::any Resolver::visitForStmt(ForStmt *node) {
    if (node->decl) {
        node->decl->accept(this);
    }
    if (node->cond) {
        if (!isCondition(node->cond.get(), this)) {
            error("for statement expr is not a bool");
        }
    }
    for (auto &u : node->updaters) {
        resolve(u.get());
    }
    inLoop = true;
    node->body->accept(this);
    inLoop = false;
    return nullptr;
}

std::any Resolver::visitContinueStmt(ContinueStmt *node) {
    if (!inLoop) {
        error("continue in outside of loop");
    }
    if (node->label) error("continue label");
    return nullptr;
}

std::any Resolver::visitBreakStmt(BreakStmt *node) {
    if (!inLoop) {
        error("break in outside of loop");
    }
    if (node->label) error("break label");
    return nullptr;
}

std::any Resolver::visitArrayExpr(ArrayExpr *node) {
    if (node->isSized()) {
        auto elemType = resolve(node->list[0]).type;
        return RType(new ArrayType(elemType, node->size.value()));
    } else {
        auto inner = resolve(node->list[0]).type;
        for (int i = 1; i < node->list.size(); i++) {
            auto t = resolve(node->list[i]).type;
            if (!subType(inner, t)) {
                error("array element type mismatch");
            }
        }
        return RType(new ArrayType(inner, node->list.size()));
    }
}