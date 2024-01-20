#include "Resolver.h"
#include "MethodResolver.h"
#include "TypeUtils.h"
#include "parser/Parser.h"
#include "parser/Util.h"
#include <any>
#include <list>
#include <memory>
#include <unordered_set>

bool Config::verbose = true;
bool Config::rvo_ptr = false;
bool Config::debug = true;

bool isCondition(Expression *e, Resolver *r) {
    return r->getType(e).print() == "bool";
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

Type copy(const Type &arg) {
    AstCopier copier;
    auto tmp = arg;
    return *(Type *) std::any_cast<Expression *>(tmp.accept(&copier));
}

RType RType::clone() {
    auto res = RType(type);
    res.unit = unit;
    res.targetDecl = targetDecl;
    res.targetMethod = targetMethod;
    res.vh = vh;
    if (value) {
        res.value = value.value();
    }
    return res;
}

RType makeSimple(const std::string &name) {
    return RType(Type(name));
}

RType binCast(const std::string &t1, const std::string &t2) {
    if (t1 == t2) return makeSimple(t1);
    if (t1 == "f64" || t2 == "f64") return makeSimple("f64");
    if (t1 == "f32" || t2 == "f32") return makeSimple("f32");
    if (t1 == "i64" || t2 == "i64") return makeSimple("i64");
    if (t1 == "u64" || t2 == "u64") return makeSimple("u64");
    if (t1 == "u32" || t2 == "u32") return makeSimple("u32");
    if (t1 == "i32" || t2 == "i32") return makeSimple("i32");
    if (t1 == "i16" || t2 == "i16") return makeSimple("i16");
    throw std::runtime_error("binCast " + t1 + ", " + t2);
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

std::shared_ptr<Resolver> Resolver::getResolver(ImportStmt &is, const std::string &root) {
    return Resolver::getResolver(root + "/" + join(is.list, "/") + ".x", root);
}

void Resolver::err(Node *e, const std::string &msg) {
    std::string s = unit->path + ":" + std::to_string(e->line) + "\n";
    if (curMethod) {
        s += "in " + printMethod(curMethod) + "\n";
    }
    auto expr = dynamic_cast<Expression *>(e);
    if (expr) {
        s += expr->print() + " ";
    }
    s += msg;
    error(s);
}

void Resolver::err(const std::string &msg) {
    if (curMethod) {
        std::string s = format("%s\nin %s\n%s", unit->path.c_str(), printMethod(curMethod).c_str(), msg.c_str());
        error(s);
    } else {
        std::string s = format("%s\n%s", unit->path.c_str(), msg.c_str());
        error(s);
    }
}

std::any Generator::visitType(Type *type) {
    return (Expression *) new Type(make(*type, map));
}

//replace any type in decl with src by same index
Type Generator::make(const Type &type, const std::map<std::string, Type> &map) {
    if (type.isPointer() || type.isSlice() || type.isArray()) {
        auto scope = make(*type.scope, map);
        auto res = Type(type.kind, scope);
        res.size = type.size;
        return res;
    }
    auto str = type.print();
    if (map.contains(str)) {
        return map.at(str);
    }
    Type res = type;
    if (type.scope) {
        res.set(make(*type.scope, map));
    }
    for (int i = 0; i < res.typeArgs.size(); ++i) {
        auto &ta = res.typeArgs[i];
        res.typeArgs[i] = make(ta, map);
    }
    return res;
}

int Resolver::findVariant(EnumDecl *decl, const std::string &name) {
    for (int i = 0; i < decl->variants.size(); i++) {
        if (decl->variants[i].name == name) {
            return i;
        }
    }
    throw std::runtime_error("unknown variant: " + name + " of type " + decl->type.print());
}

void Scope::add(const VarHolder &f) {
    for (auto &prev : list) {
        if (prev.name == f.name) {
            throw std::runtime_error("variable " + f.name + " already declared in the same scope");
        }
    }
    list.push_back(std::move(f));
}

void Scope::clear() { list.clear(); }

VarHolder *Scope::find(const std::string &name) {
    for (auto &vh : list) {
        if (vh.name == name) {
            return &vh;
        }
    }
    return nullptr;
}

std::string Resolver::getId(Expression *e) {
    auto res = e->accept(&idgen);
    if (res.has_value()) {
        return std::any_cast<std::string>(res);
    }
    throw std::runtime_error("id: " + e->print());
}

std::unordered_map<std::string, std::shared_ptr<Resolver>> Resolver::resolverMap;
std::vector<std::string> Resolver::prelude = {"Box", "List", "str", "String", "Option", "ops"};

Resolver::Resolver(std::shared_ptr<Unit> unit, const std::string &root) : unit(unit), root(root), idgen(IdGen{this}) {
}

void Resolver::init_prelude() {
    for (auto &pre : prelude) {
        getResolver("../tests/src/std/" + pre + ".x", "../tests/src");
    }
}

bool has(std::vector<ImportStmt> &arr, ImportStmt &is) {
    for (auto &i : arr) {
        auto s1 = join(i.list, "/");
        auto s2 = join(is.list, "/");
        if (s1 == s2) return true;
    }
    return false;
}

bool contains(const std::vector<std::string> &vec, const std::string &elem) {
    for (auto const &e : vec) {
        if (e == elem) {
            return true;
        }
    }
    return false;
}

std::string get_relative_root(const std::string &path, const std::string &root) {
    //print("cur=" + path + ", root=" + root);
    if (path.starts_with(root)) {
        return path.substr(root.length() + 1);//+1 for slash
    }
    return path;
}

std::vector<ImportStmt> Resolver::get_imports() {
    std::vector<ImportStmt> imports;
    auto cur = get_relative_root(unit->path, root);
    for (auto &pre : prelude) {
        //skip self unit being prelude
        if (cur == "std/" + pre + ".x") continue;
        ImportStmt is;
        is.list.push_back("std");
        is.list.push_back(pre);
        imports.push_back(std::move(is));
    }
    for (auto &is : unit->imports) {
        //ignore prelude imports
        if (!has(imports, is)) {
            imports.push_back(is);
        }
    }
    if (curMethod && !curMethod->typeArgs.empty()) {
        for (auto &is : curMethod->unit->imports) {
            if (has(imports, is)) continue;
            //skip self being cycle
            if (unit->path == getPath(is)) continue;
            imports.push_back(is);
        }
    }
    return imports;
}

void Resolver::newScope() {
    scopes.push_back(Scope{});
    max_scope++;
}

void Resolver::dropScope() {
    //todo clear;
    scopes.pop_back();
}

void Resolver::addScope(std::string &name, const Type &type, bool prm) {
    scopes.back().add(VarHolder(name, type, prm));
}

void dump(Resolver *r) {
    for (auto &[k, v] : r->cache) {
        print(k);
        for (auto &[k2, v2] : v) {
            print(k2 + "=" + v2.type.print());
        }
        print("");
    }
}

void dump(Method *node) {
    print(node->print());
}

void Resolver::resolveAll() {
    if (isResolved) return;
    isResolved = true;
    init();
    newScope();//globals
    for (Global &g : unit->globals) {
        auto rhs = resolve(g.expr);
        if (g.type) {
            auto type = getType(g.type.value());
            //todo check
            auto err_opt = MethodResolver::isCompatible(rhs.type, type);
            if (err_opt) {
                std::string msg = "variable type mismatch '" + g.name + "'\n";
                msg += "expected: " + type.print() + " got " + rhs.type.print();
                msg += "\n" + err_opt.value();
                err(msg);
            }
        }
        addScope(g.name, rhs.type, false);
    }
    for (auto &item : unit->items) {
        item->accept(this);
    }
    int j = 0;
    while (true) {
        //todo dont visit used type methods they already visited
        int old = usedTypes.size();
        for (; j < usedTypes.size(); j++) {
            auto gt = usedTypes[j];
            gt->accept(this);
        }
        if (old == usedTypes.size()) break;
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

void initSelf(Unit *unit) {
    for (auto &item : unit->items) {
        if (item->isImpl()) {
            auto imp = (Impl *) item.get();
            for (auto &m : imp->methods) {
                if (m.self && !m.self->type) {
                    m.self->type = clone(makeSelf(imp->type));
                }
            }
        }
    }
}

MethodCall *newStr(std::shared_ptr<Unit> &unit, const std::string &name) {
    auto mc = new MethodCall;
    mc->is_static = true;
    mc->line = unit->lastLine;
    mc->scope.reset(new Type("String"));
    mc->name = "new";
    if (!name.empty()) {
        auto lit = new Literal(Literal::STR, "\"" + name + "\"");
        lit->line = unit->lastLine;
        mc->args.push_back(lit);
    }
    return mc;
}
Ptr<ExprStmt> newPrint(std::shared_ptr<Unit> &unit, const std::string &scope, Expression *e) {
    auto mc = new MethodCall;
    mc->line = unit->lastLine;
    mc->scope.reset(new SimpleName(scope));
    mc->name = "print";
    mc->args.push_back(e);
    auto res = std::make_unique<ExprStmt>(mc);
    res->line = unit->lastLine;
    return res;
}
//scope.print(str);
Ptr<ExprStmt> newPrint(std::shared_ptr<Unit> &unit, const std::string &scope, const std::string &str) {
    auto mc = new MethodCall;
    mc->line = unit->lastLine;
    mc->scope.reset(new SimpleName(scope));
    mc->name = "print";
    auto lit = new Literal(Literal::STR, "\"" + str + "\"");
    lit->line = unit->lastLine;
    mc->args.push_back(lit);
    auto res = std::make_unique<ExprStmt>(mc);
    res->line = unit->lastLine;
    return res;
}

Ptr<ReturnStmt> makeRet(std::shared_ptr<Unit> unit, Expression *e) {
    auto ret = std::make_unique<ReturnStmt>();
    ret->line = ++unit->lastLine;
    ret->expr.reset(e);
    return ret;
}

//Debug::debug(e, f)
Ptr<ExprStmt> makeDebug(std::shared_ptr<Unit> &unit, Expression *e, Type &type, const std::string &fmt) {
    auto mc = new MethodCall;
    mc->line = ++unit->lastLine;
    mc->is_static = true;
    mc->scope.reset(new Type("Debug"));
    mc->name = "debug";
    if (!type.isPointer()) {
        e = new RefExpr(std::unique_ptr<Expression>(e));
    }
    mc->args.push_back(e);
    mc->args.push_back(new SimpleName(fmt));
    auto res = std::make_unique<ExprStmt>(mc);
    res->line = unit->lastLine;
    return res;
}

FieldAccess *makeFa(const std::string &scope, const std::string &name) {
    auto fa = new FieldAccess;
    fa->scope = new SimpleName(scope);
    fa->name = name;
    return fa;
}
FieldAccess *makeFa(const std::string &name) {
    auto fa = new FieldAccess;
    fa->scope = new SimpleName("self");
    fa->name = name;
    return fa;
}

std::unique_ptr<Impl> Resolver::derive(BaseDecl *bd) {
    int line = unit->lastLine;
    Method m(unit.get());
    m.name = "debug";
    Param s("self", clone(makeSelf(bd->type)));
    m.self = std::move(s);
    m.type = Type("void");
    Param fp("f", Type(Type::Pointer, Type("Fmt")));
    m.params.push_back(std::move(fp));
    auto bl = new Block;
    m.body.reset(bl);
    if (bd->isEnum()) {
        auto ed = (EnumDecl *) bd;
        for (int i = 0; i < ed->variants.size(); i++) {
            auto &ev = ed->variants[i];
            auto ifs = std::make_unique<IfLetStmt>();
            ifs->line = line;
            ifs->type = (Type(clone(bd->type), ev.name));
            for (auto &fd : ev.fields) {
                //todo make this ptr
                ifs->args.push_back(ArgBind(fd.name));
            }
            ifs->rhs.reset(new SimpleName("self"));
            auto then = new Block;
            ifs->thenStmt.reset(then);
            then->list.push_back(newPrint(unit, "f", bd->type.print() + "::" + ev.name));
            if (!ev.fields.empty()) {
                then->list.push_back(newPrint(unit, "f", "{"));
                int j = 0;
                for (auto &fd : ev.fields) {
                    if (j++ > 0) then->list.push_back(newPrint(unit, "f", ", "));
                    then->list.push_back(newPrint(unit, "f", fd.name + ": "));
                    then->list.push_back(makeDebug(unit, new SimpleName(fd.name), fd.type, "f"));
                }
                then->list.push_back(newPrint(unit, "f", "}"));
            }
            bl->list.push_back(std::move(ifs));
        }
    } else {
        auto sd = (StructDecl *) bd;
        bl->list.push_back(newPrint(unit, "f", sd->type.name + "{"));
        int i = 0;
        for (auto &fd : sd->fields) {
            bl->list.push_back(newPrint(unit, "f", (i > 0 ? ", " : "") + fd.name + ": "));
            //auto ts = fd.type.print();
            bl->list.push_back(makeDebug(unit, makeFa(fd.name), fd.type, "f"));
            i++;
        }
        bl->list.push_back(newPrint(unit, "f", "}"));
    }
    auto imp = std::make_unique<Impl>(bd->type);
    imp->trait_name = Type("Debug");
    imp->type_params = bd->type.typeArgs;
    m.parent = imp.get();
    imp->methods.push_back(std::move(m));
    auto tr = resolve(Type("Debug")).trait;
    for (auto &mm : tr->methods) {
        if (mm.body) {
            AstCopier copier;
            auto m2 = std::any_cast<Method *>(mm.accept(&copier));
            imp->methods.push_back(std::move(*m2));
        }
    }
    return imp;
}

void init_impl(Impl *impl, Resolver *r) {
    if (impl->type_params.empty()) {
        return;
    }
    auto &arr = impl->type.typeArgs;
    //resolve non generic type args
    for (auto &ta : arr) {
        if (!hasGeneric(ta, impl->type_params)) {
            r->resolve(ta);
        }
    }
    for (auto &m : impl->methods) {
        m.isGeneric = true;
    }
}

void Resolver::init() {
    if (is_init) return;
    is_init = true;
    std::vector<std::unique_ptr<Impl>> newItems;
    for (auto &item : unit->items) {
        if (item->isClass() || item->isEnum()) {
            auto bd = dynamic_cast<BaseDecl *>(item.get());
            auto res = makeSimple(bd->getName());
            res.unit = unit.get();
            res.targetDecl = bd;
            addType(bd->getName(), res);
            if (!bd->derives.empty()) {
                newItems.push_back(derive(bd));
                init_impl(newItems.back().get(), this);
            }
        } else if (item->isTrait()) {
            auto tr = (Trait *) item.get();
            auto res = makeSimple(tr->type.name);
            res.unit = unit.get();
            res.trait = tr;
            addType(tr->type.name, res);
        } else if (item->isImpl()) {
            auto impl = dynamic_cast<Impl *>(item.get());
            init_impl(impl, this);
        } else if (item->isType()) {
            auto ti = (TypeItem *) item.get();
            addType(ti->name, resolve(&ti->rhs));
        }
    }//for
    for (auto &ni : newItems) {
        unit->items.push_back(std::move(ni));
    }
    initSelf(unit.get());
}

RType Resolver::resolve(Expression *expr) {
    //print("resolve " + expr->print());
    auto idtmp = expr->accept(&idgen);
    if (!idtmp.has_value()) {
        return std::any_cast<RType>(expr->accept(this));
    }
    auto id = std::any_cast<std::string>(idtmp);
    auto scp = printMethod(curMethod);
    auto &map = cache[scp];
    auto it = map.find(id);
    if (it != map.end()) {
        return it->second;
    }
    auto res = std::any_cast<RType>(expr->accept(this));
    map[id] = res;
    return res;
}

Type Resolver::getType(Expression *expr) {
    return resolve(expr).type;
}

bool Resolver::isCyclic(const Type &type0, BaseDecl *target) {
    auto type = getType(type0);
    if (type.isPointer()) return false;
    if (type.isArray()) {
        return isCyclic(*type.scope.get(), target);
    }
    if (type.isSlice()) return false;
    if (!isStruct(type)) return false;
    if (type.print() == target->type.print()) {
        return true;
    }
    auto bd = resolve(type).targetDecl;
    if (bd->base && isCyclic(bd->base.value(), target)) {
        return true;
    }
    if (bd->isEnum()) {
        auto en = dynamic_cast<EnumDecl *>(bd);
        for (auto &ev : en->variants) {
            for (auto &f : ev.fields) {
                if (isCyclic(f.type, target)) {
                    return true;
                }
            }
        }
    } else {
        auto td = dynamic_cast<StructDecl *>(bd);
        for (auto &fd : td->fields) {
            if (isCyclic(fd.type, target)) {
                return true;
            }
        }
    }
    return false;
}
std::any Resolver::visitEnumDecl(EnumDecl *node) {
    if (node->isGeneric) {
        return nullptr;
    }
    if (!node->isResolved) {
        node->isResolved = true;
        for (auto &ev : node->variants) {
            for (auto &ep : ev.fields) {
                resolve(ep.type);
                if (isCyclic(ep.type, node)) {
                    err("cyclic type " + node->type.print());
                }
            }
        }
    }
    return getTypeCached(node->type.print());
}

RType Resolver::getTypeCached(const std::string &name) {
    auto it = typeMap.find(name);
    if (it == typeMap.end()) error("not cached " + name);
    return it->second;
}

void Resolver::addType(const std::string &name, const RType &rt) {
    typeMap[name] = rt;
}

std::any Resolver::visitStructDecl(StructDecl *node) {
    if (node->isGeneric) {
        return nullptr;
    }
    //if (!node->isResolved) {
    node->isResolved = true;
    for (auto &fd : node->fields) {
        fd.accept(this);
        if (isCyclic(fd.type, node)) {
            err("cyclic type " + node->type.print());
        }
    }
    //}
    return getTypeCached(node->type.print());
}

std::vector<Method> &Resolver::get_trait_methods(const Type &type) {
    auto rt = resolve(type);
    return rt.trait->methods;
}

std::string mangle2(Method &m, const Type &parent) {
    std::string s = m.name;
    std::map<std::string, Type> map = {{"Self", parent}};
    for (auto &p : m.params) {
        s += "_";
        auto ty = Generator::make(p.type.value(), map);
        s += ty.print();
    }
    return s;
}

std::any Resolver::visitImpl(Impl *node) {
    if (!node->type_params.empty()) {
        return nullptr;
    }
    curImpl = node;
    if (node->trait_name) {
        //mark required methods
        std::map<std::string, Method *> required;
        auto &methods = get_trait_methods(*node->trait_name);
        for (auto &m : methods) {
            if (!m.body) {
                required[mangle2(m, node->type)] = &m;
            }
        }
        //delete the matching required method
        for (auto &m : node->methods) {
            if (!m.typeArgs.empty()) {
                continue;
            }
            m.accept(this);
            auto mng = mangle2(m, node->type);
            if (required.contains(mng)) {
                required.erase(mng);
            }
        }
        if (!required.empty()) {
            std::string msg;
            for (auto &[mng, m] : required) {
                msg += "method " + printMethod(m) + " not implemented for " + node->type.print();
            }
            error(msg);
        }
    } else {
        for (auto &m : node->methods) {
            if (!m.typeArgs.empty()) {
                continue;
            }
            m.accept(this);
        }
    }
    curImpl = nullptr;
    return resolve(node->type);
}

std::any Resolver::visitTrait(Trait *node) {
    //todo
    return nullptr;
}

std::any Resolver::visitExtern(Extern *node) {
    for (auto &m : node->methods) {
        if (!m.typeArgs.empty()) {
            continue;
        }
        m.accept(this);
    }
    return nullptr;
}

std::any Resolver::visitFieldDecl(FieldDecl *node) {
    auto res = resolve(node->type).clone();
    //todo remove this
    //res.vh = VarHolder(node->name, res.type);
    return res;
}

bool Resolver::do_override(Method *m1, Method *m2) {
    if (m1->name != m2->name || !m2->isVirtual || !m2->self || !m1->self || m1->params.size() != m2->params.size()) {
        return false;
    }
    for (int i = 1; i < m1->params.size(); i++) {
        if (m1->params[i].type->print() != m2->params[i].type->print()) {
            return false;
        }
    }
    return true;
}

//find base method that we override
Method *Resolver::isOverride(Method *method) {
    if (!method->self) return nullptr;
    auto cur = *method->self->type;
    while (true) {
        auto decl = resolve(cur).targetDecl;
        if (!decl || !decl->base) return nullptr;
        auto base = *decl->base;
        for (auto &item : unit->items) {//todo not just this unit
            if (!item->isImpl()) continue;
            auto imp = (Impl *) item.get();
            if (imp->type.name != base.name) continue;
            for (auto &m : imp->methods) {
                if (do_override(method, &m)) return &m;
            }
        }
        cur = base;
    }
    return nullptr;
}

std::any Resolver::visitMethod(Method *m) {
    if (m->isGeneric) {
        return nullptr;
    }
    if (is_main(m) && m->type.print() != "void" && m->type.print() != "i32") {
        err("main method's return type must be 'void' or 'i32'");
    }
    curMethod = m;
    //print("visitMethod "+ printMethod(m));
    if (m->isVirtual && !m->self) {
        err("virtual method must have self parameter");
    }
    //todo check if both virtual and override
    auto orr = isOverride(m);
    if (orr) {
        print(printMethod(m) + " overrides " + printMethod(orr));
        overrideMap[m] = orr;
    }
    auto res = resolve(m->type).clone();
    res.targetMethod = m;
    max_scope = 0;
    newScope();
    if (m->self) {
        if (!m->self->type) err("self type is not set");
        addScope(m->self->name, *m->self->type, true);
        m->self->accept(this);
    }
    for (auto &prm : m->params) {
        addScope(prm.name, *prm.type, true);
        prm.accept(this);
    }
    if (m->body) {
        m->body->accept(this);
        //todo check unreachable
        if (!m->type.isVoid() && !isReturnLast(m->body.get())) {
            err("non void function must return a value");
        }
    }
    dropScope();
    curMethod = nullptr;
    //print("exiting visitMethod "+ printMethod(m));
    return res;
}

std::any Resolver::visitParam(Param *p) {
    return resolve(*p->type).clone();
}

std::any Resolver::visitFragment(Fragment *f) {
    auto rhs = resolve(f->rhs.get());
    if (!f->type) return rhs.clone();
    auto res = resolve(*f->type);
    auto err_opt = MethodResolver::isCompatible(rhs, res.type);
    if (err_opt) {
        std::string msg = "variable type mismatch '" + f->name + "'\n";
        msg += "expected: " + res.type.print() + " got " + rhs.type.print();
        msg += "\n" + err_opt.value();
        err(f, msg);
    }
    return res;
}

std::any Resolver::visitVarDeclExpr(VarDeclExpr *vd) {
    for (auto &f : vd->list) {
        auto rt = std::any_cast<RType>(f.accept(this));
        addScope(f.name, rt.type);
    }
    return nullptr;
}

std::any Resolver::visitVarDecl(VarDecl *vd) {
    visitVarDeclExpr(vd->decl);
    return nullptr;
}

BaseDecl *generateDecl(const Type &type, BaseDecl *decl) {
    std::map<std::string, Type> map;
    for (int i = 0; i < decl->type.typeArgs.size(); i++) {
        auto &ta = decl->type.typeArgs[i];
        map[ta.name] = type.typeArgs[i];
    }
    if (decl->isEnum()) {
        auto res = new EnumDecl;
        res->unit = decl->unit;
        res->type = clone(type);
        auto ed = dynamic_cast<EnumDecl *>(decl);
        for (auto &ev : ed->variants) {
            EnumVariant ev2;
            ev2.name = ev.name;
            for (auto &field : ev.fields) {
                auto ftype = Generator::make(field.type, map);
                ev2.fields.push_back(FieldDecl(field.name, ftype));
            }
            res->variants.push_back(std::move(ev2));
        }
        return res;
    } else {
        auto res = new StructDecl;
        res->unit = decl->unit;
        res->type = clone(type);
        auto td = dynamic_cast<StructDecl *>(decl);
        for (auto &field : td->fields) {
            auto ftype = Generator::make(field.type, map);
            res->fields.push_back(FieldDecl(field.name, ftype));
        }
        return res;
    }
}

BaseDecl *Resolver::getDecl(const Type &type) {
    auto it = typeMap.find(type.print());
    if (it != typeMap.end()) {
        return it->second.targetDecl;
    }
    return nullptr;
}

std::any Resolver::visitType(Type *type) {
    auto str = type->print();
    auto it = typeMap.find(str);
    if (it != typeMap.end()) {
        return it->second;
    }
    if (type->isPrim() || type->isVoid()) {
        auto res = RType(*type);
        addType(str, res);
        return res;
    }
    if (type->isPointer()) {
        auto rt = resolve(type->scope.get());
        auto res = rt.clone();
        res.type = Type(Type::Pointer, rt.type);
        addType(str, res);
        return res;
    }
    if (type->isSlice()) {
        auto rt = resolve(type->scope.get());
        auto res = RType(Type(Type::Slice, clone(rt.type)));
        addType(str, res);
        return res;
    }
    if (type->isArray()) {
        auto rt = resolve(type->scope.get());
        auto res = RType(Type(clone(rt.type), type->size));
        addType(str, res);
        return res;
    }
    if (str == "Self" && curMethod->parent) {
        auto imp = dynamic_cast<Impl *>(curMethod->parent);
        return resolve(&imp->type);
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
        auto res = getTypeCached(ed->type.print());
        addType(str, res);
        return res;
    }
    /*if (curMethod && curMethod->self) {
        auto decl = getDecl(*curMethod->self->type);
        if (decl && decl->isEnum()) {
            auto ed = (EnumDecl *) decl;
            for (auto &v : ed->variants) {
                if (v.name == type->name) {
                    //enum variant without scope(same impl)
                    auto res = getTypeCached(ed->type.print());
                    //addType(str, res);
                    return res;
                }
            }
        }
    }*/

    BaseDecl *target = nullptr;
    if (!type->typeArgs.empty()) {
        for (const auto &ta : type->typeArgs) {
            resolve(ta);
        }
        //we looking for generic type
        auto cached = typeMap.find(type->name);
        if (cached != typeMap.end()) {
            target = cached->second.targetDecl;
        } else {
            //generic from imports
        }
    }
    if (!target) {
        for (auto &is : get_imports()) {
            auto resolver = getResolver(is, root);
            resolver->init();
            //try full type
            if (type->typeArgs.empty()) {
                //non generic type
                auto cached = resolver->typeMap.find(str);
                if (cached != resolver->typeMap.end()) {
                    auto res = cached->second;
                    addType(str, res);
                    if (res.targetDecl) {
                        if (!res.targetDecl->isGeneric) {
                            addUsed(res.targetDecl);
                        }
                    }//todo trait
                    return res;
                }
            } else {
                //generic type
                //try root type
                auto cached = resolver->typeMap.find(type->name);
                if (cached != resolver->typeMap.end()) {
                    target = cached->second.targetDecl;
                    break;
                }
            }
        }
    }
    if (!target) {
        err(type, "couldn't find type: " + str);
    }
    //generic
    if (type->typeArgs.empty()) {
        //inferred later
        RType res(clone(target->type));
        res.targetDecl = target;
        addType(str, res);
        return res;
    }
    if (type->typeArgs.size() != target->type.typeArgs.size()) {
        error("type arguments size not matched");
    }
    auto decl = generateDecl(*type, target);
    //print("type="+str+"\n"+decl->print());
    RType res(Type(type->name));
    for (auto &ta : type->typeArgs) {
        res.type.typeArgs.push_back(clone(ta));
    }
    res.targetDecl = decl;
    addUsed(decl);
    addType(str, res);
    return res;
}

void Resolver::addUsed(BaseDecl *bd) {
    for (auto prev : usedTypes) {
        if (prev->type.print() == bd->type.print()) return;
    }
    usedTypes.push_back(bd);
}

SimpleName *find_base(Expression *e) {
    auto sn = dynamic_cast<SimpleName *>(e);
    if (sn) return sn;
    auto aa = dynamic_cast<ArrayAccess *>(e);
    if (aa) return find_base(aa->array);
    auto fa = dynamic_cast<FieldAccess *>(e);
    if (fa) return find_base(fa->scope);
    auto de = dynamic_cast<DerefExpr *>(e);
    if (de) return find_base(de->expr.get());
    throw std::runtime_error("todo is_param: " + e->print());
}

void handleMut(Resolver *r, MutKind kind, const std::string &name) {
    auto id = prm_id(*r->curMethod, name);
    r->mut_params[id] = kind;
}

void does_alloc(Expression *e, Resolver *r) {
    //todo func call can mutate too
    auto sn = dynamic_cast<SimpleName *>(e);
    if (sn) {
        auto rt = r->resolve(sn);
        if (rt.vh->prm) {
            handleMut(r, MutKind::WHOLE, sn->name);
        }
        return;
    }
    auto de = dynamic_cast<DerefExpr *>(e);
    if (de) {
        auto sn2 = dynamic_cast<SimpleName *>(de->expr.get());
        if (!sn2) return;
        auto rt = r->resolve(sn2);
        if (rt.vh->prm) {
            handleMut(r, MutKind::DEREF, sn2->name);
        }
        return;
    }
    sn = find_base(e);
    auto rt = r->resolve(sn);
    if (rt.vh->prm) {
        handleMut(r, MutKind::FIELD, sn->name);
    }
}

std::any Resolver::visitAssign(Assign *node) {
    auto t1 = resolve(node->left);
    auto t2 = resolve(node->right);
    if (MethodResolver::isCompatible(t2, t1.type)) {
        auto msg = format("cannot assign %s\n%s=%s", node->print().c_str(), t1.type.print().c_str(), t2.type.print().c_str());
        error(msg);
    }
    //does_alloc(node->left, this);
    return t1;
}

std::any Resolver::visitInfix(Infix *node) {
    //todo mut
    auto rt1 = resolve(node->left);
    auto rt2 = resolve(node->right);
    if (rt1.type.isVoid() || rt2.type.isVoid()) {
        error("operation on void type");
    }
    if (rt1.type.isString() || rt2.type.isString()) {
        error("string op not supported yet");
    }
    if (rt1.targetDecl && node->op == "==") {
        if (rt1.type.print() == rt2.type.print())
            return makeSimple("bool");
    }
    if (!rt1.type.isPrim() || !rt2.type.isPrim()) {
        err(node, "infix on non prim type: " + rt1.type.print() + " vs " + rt2.type.print());
    }
    /*if (node->op == "==" || node->op == "!=") {
        auto u1 = isUnsigned(rt1.type);
        auto u2 = isUnsigned(rt2.type);
        if (!u1 && !rt1.value && u2 || u1 && !u2 && !rt2.value){
          err(node, "both comparision operands must be same type");
        }
    }*/
    if (isComp(node->op)) {
        return makeSimple("bool");
    } else if (node->op == "&&" || node->op == "||") {
        if (rt1.type.print() != "bool") {
            error("infix lhs is not boolean: " + node->left->print());
        }
        if (rt2.type.print() != "bool") {
            error("infix rhs is not boolean: " + node->right->print());
        }
        return makeSimple("bool");
    } else {
        if (node->op == "-" && isUnsigned(rt1.type)) {
            err(node, "this will overflow");
        }
        auto s1 = rt1.type.print();
        auto s2 = rt2.type.print();
        return binCast(s1, s2);
    }
}

std::any Resolver::visitUnary(Unary *node) {
    //todo check unsigned
    auto res = resolve(node->expr);
    if (node->op == "!") {
        if (res.type.print() != "bool") {
            error("unary on non boolean: " + node->print());
        }
    } else {
        if (res.type.print() == "bool" || !res.type.isPrim()) {
            error("unary on non interal: " + node->print());
        }
        if (node->op == "--" || node->op == "++") {
            if (!iof<SimpleName *>(node->expr) && !iof<FieldAccess *>(node->expr)) {
                error("prefix on non variable: " + node->print());
            }
        }
    }
    if (node->op == "-" && res.value) {
        res = res.clone();
        res.value = "-" + res.value.value();
    }
    return res;
}

std::any Resolver::visitSimpleName(SimpleName *node) {
    for (int i = scopes.size() - 1; i >= 0; i--) {
        auto vh = scopes[i].find(node->name);
        if (vh) {
            auto res = resolve(vh->type).clone();
            res.vh = *vh;
            return res;
        }
    }
    err(node, "unknown identifier: " + node->name);
    return {};
}

std::pair<StructDecl *, int> Resolver::findField(const std::string &name, BaseDecl *decl, const Type &type) {
    auto cur = decl;
    while (cur && true) {
        if (cur->isClass()) {
            auto sd = (StructDecl *) cur;
            int idx = 0;
            for (auto &fd : sd->fields) {
                if (fd.name == name) {
                    return std::make_pair(sd, idx);
                }
                idx++;
            }
        }
        if (cur->base) {
            auto base = resolve(*cur->base).targetDecl;
            cur = base;
        } else {
            break;
        }
    }
    return std::make_pair(nullptr, -1);
}

std::any Resolver::visitFieldAccess(FieldAccess *node) {
    auto scp = resolve(node->scope);
    if (scp.type.isPointer() && scp.type.scope->isPointer()) {
        err(node, "invalid field " + node->name + " of " + scp.type.print());
    }
    auto decl = scp.targetDecl;
    if (!decl) {
        err(node, "invalid field " + node->name + " of " + scp.type.print());
    }
    auto [sd, idx] = findField(node->name, decl, scp.type);
    if (idx == -1) {
        err(node, "invalid field " + node->name + " of " + scp.type.print());
    }
    auto &fd = sd->fields[idx];
    return std::any_cast<RType>(fd.accept(this));
}

std::any Resolver::visitLiteral(Literal *node) {
    if (node->suffix) {
        //check max value
        if (max_for(*node->suffix) < stoll(node->val)) {
            err(node, "literal out of range");
        }
        return RType(*node->suffix);
    }
    auto type = node->type;
    if (type == Literal::STR) {
        return RType(Type("str"));
    } else if (type == Literal::BOOL) {
        return RType(Type("bool"));
    } else if (type == Literal::FLOAT) {
        auto res = RType(Type("f32"));
        res.value = node->val;
        return res;
    } else if (type == Literal::INT) {
        auto res = RType(Type("i32"));
        res.value = node->val;
        return res;
    } else if (type == Literal::CHAR) {
        auto res = RType(Type("u32"));
        res.value = std::to_string(node->val[0]);
        return res;
    }
    err(node, "unknown literal");
    return {};
}

bool Resolver::is_base_of(const Type &base, BaseDecl *d) {
    while (d->base) {
        if (d->base->print() == base.print()) return true;
        d = resolve(*d->base).targetDecl;
    }
    return false;
}

std::any Resolver::visitAsExpr(AsExpr *node) {
    auto left = resolve(node->expr);
    auto right = resolve(node->type);
    //prim->prim
    if (left.type.isPrim() && right.type.isPrim()) {
        return right;
    }
    //derived->base
    if (left.targetDecl && left.targetDecl->base) {
        auto cur = left.targetDecl;
        while (cur && cur->base) {
            if (cur->base->print() + "*" == right.type.print()) return right;
            cur = resolve(*cur->base).targetDecl;
        }
    }
    if (right.type.isPointer()) {
        return right;
    }
    if (left.type.isPointer() && right.type.print() == "u64") {
        return makeSimple("u64");
    }
    throw std::runtime_error("invalid as expr " + node->print());
}

std::any Resolver::visitRefExpr(RefExpr *node) {
    auto e = node->expr.get();
    //todo field access
    if (!iof<SimpleName *>(e) && !iof<ArrayAccess *>(e) && !iof<FieldAccess *>(e)) {
        error("ref expr is not supported: " + node->expr->print());
    }
    auto inner = resolve(node->expr.get()).clone();
    inner.type = Type(Type::Pointer, inner.type);
    return inner;
}

std::any Resolver::visitDerefExpr(DerefExpr *node) {
    auto rt = resolve(node->expr.get());
    auto &inner = rt.type;
    if (!inner.isPointer()) {
        error("deref expr is not pointer: " + node->expr->print());
    }
    auto res = rt.clone();
    res.type = *inner.scope.get();
    return res;
}

std::any Resolver::visitAssertStmt(AssertStmt *node) {
    if (!isCondition(node->expr.get(), this)) {
        error("assert expr is not boolean expr: " + node->expr->print());
    }
    return nullptr;
}

std::any Resolver::visitIfLetStmt(IfLetStmt *node) {
    auto rt = resolve(node->type);
    if (!rt.targetDecl->isEnum()) {
        err(node, "type of if let is not enum: " + node->type.print());
    }
    auto rhs = resolve(node->rhs.get());
    if (!rhs.targetDecl->isEnum()) {
        err(node, "if let rhs is not enum: " + node->rhs->print());
    }
    auto decl = dynamic_cast<EnumDecl *>(rt.targetDecl);
    int index = findVariant(decl, node->type.name);
    auto &variant = decl->variants[index];
    if (variant.fields.size() != node->args.size()) {
        err(node, "if let args size mismatch: " + join(node->args, ", "));
    }
    int i = 0;
    newScope();
    for (auto &arg : node->args) {
        if (arg.ptr) {
            addScope(arg.name, Type(Type::Pointer, variant.fields[i].type));
        } else {
            addScope(arg.name, variant.fields[i].type);
        }
        i++;
    }
    node->thenStmt->accept(this);
    dropScope();
    if (node->elseStmt) {
        newScope();
        node->elseStmt->accept(this);
        dropScope();
    }
    return nullptr;
}

std::any Resolver::visitParExpr(ParExpr *node) {
    return resolve(node->expr);
}

std::any Resolver::visitExprStmt(ExprStmt *node) {
    if (!iof<MethodCall *>(node->expr) && !iof<Assign *>(node->expr) && !iof<Unary *>(node->expr)) {
        error("invalid expr statement: " + node->print());
    }
    resolve(node->expr);
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
        err(node->expr.get(), "if condition is not a boolean");
    }
    newScope();
    node->thenStmt->accept(this);
    dropScope();
    if (node->elseStmt) {
        newScope();
        node->elseStmt->accept(this);
        dropScope();
    }
    return nullptr;
}

std::any Resolver::visitReturnStmt(ReturnStmt *node) {
    if (node->expr) {
        if (curMethod->type.isVoid()) {
            error("void method returns expr");
        }
        auto type = resolve(node->expr.get());
        auto mtype = getType(curMethod->type);
        if (MethodResolver::isCompatible(type, mtype)) {
            //err(node, );
            err(node, "method " + printMethod(curMethod) + " expects '" + mtype.print() + " but returned '" + type.type.print() + "' => ");
        }
    } else {
        if (!curMethod->type.isVoid()) {
            error("non-void method returns void");
        }
    }
    return nullptr;
}

std::any Resolver::visitIsExpr(IsExpr *node) {
    auto rt = resolve(node->expr);
    auto decl1 = rt.targetDecl;
    if (!decl1 || !decl1->isEnum()) {
        error("lhs of is expr is not enum: " + rt.type.print());
    }
    auto rt2 = resolve(node->rhs);
    auto decl2 = rt2.targetDecl;
    if (decl1 != decl2) {
        error("rhs is not same type with lhs " + decl2->type.print());
    }
    auto rr = dynamic_cast<Type *>(node->rhs);
    if (rr) {
        findVariant(dynamic_cast<EnumDecl *>(decl1), rr->name);
    }
    return makeSimple("bool");
}

Type Resolver::inferStruct(ObjExpr *node, bool hasNamed, const std::vector<Type> &typeArgs, std::vector<FieldDecl> &fields, const Type &type) {
    std::map<std::string, std::optional<Type>> inferMap;
    for (auto &ta : typeArgs) {
        inferMap[ta.name] = std::optional<Type>();
    }
    for (int i = 0; i < node->entries.size(); i++) {
        auto &e = node->entries[i];
        int prm_idx;
        if (hasNamed) {
            prm_idx = fieldIndex(fields, e.key.value(), type);
        } else {
            prm_idx = i;
        }
        auto arg_type = resolve(e.value);
        auto &target_type = fields[i].type;
        MethodResolver::infer(arg_type.type, target_type, inferMap);
    }
    for (auto &i : inferMap) {
        if (!i.second) {
            error("can't infer type parameter: " + i.first);
        }
    }
    auto res = Type(type.name);
    for (auto &e : inferMap) {
        res.typeArgs.push_back(*e.second);
    }
    return res;
}

std::any Resolver::visitObjExpr(ObjExpr *node) {
    bool hasNamed = false;
    bool hasNonNamed = false;
    Expression *base = nullptr;
    for (auto &e : node->entries) {
        if (e.isBase) {
            if (base) err(node, "base already set");
            base = e.value;
        } else if (e.key) {
            hasNamed = true;
        } else {
            hasNonNamed = true;
        }
    }
    if (hasNamed && hasNonNamed) {
        throw std::runtime_error("obj creation can't have mixed values");
    }
    auto res = resolve(node->type);
    if (node->isPointer) {
        res = res.clone();
        res.type = Type(Type::Pointer, res.type);
    }
    //base checks
    auto decl = res.targetDecl;
    if (decl->base && !base) {
        err(node, "base class is not initialized");
    }
    if (!decl->base && base) {
        err(node, "wasn't expecting base");
    }
    if (base) {
        auto base_ty = getType(base);
        if (base_ty.print() != decl->base->print()) {
            err(node, "invalid base class type: " + base_ty.print() + " expecting: " + decl->base->print());
        }
    }
    std::vector<FieldDecl> *fields;
    Type type;
    if (res.targetDecl->isEnum()) {
        auto ed = dynamic_cast<EnumDecl *>(res.targetDecl);
        int idx = findVariant(ed, node->type.name);
        auto &variant = ed->variants[idx];
        fields = &variant.fields;
        type = Type(ed->type, variant.name);
    } else {
        auto td = dynamic_cast<StructDecl *>(res.targetDecl);
        fields = &td->fields;
        type = td->type;
        if (td->isGeneric) {
            //infer
            auto inferred = inferStruct(node, hasNamed, td->type.typeArgs, td->fields, td->type);
            auto gen_decl = generateDecl(inferred, td);
            td = dynamic_cast<StructDecl *>(gen_decl);
            addUsed(gen_decl);
            res = resolve(gen_decl->type);
            fields = &td->fields;
        }
    }
    int fcnt = fields->size();
    if (base) fcnt++;
    if (fcnt != node->entries.size()) {
        //error(node, "incorrect number of arguments passed to object creation");
    }
    int field_idx = 0;
    std::unordered_set<std::string> names;
    for (int i = 0; i < node->entries.size(); i++) {
        auto &e = node->entries[i];
        if (e.isBase) continue;
        int prm_idx;
        if (hasNamed) {
            names.insert(e.key.value());
            prm_idx = fieldIndex(*fields, e.key.value(), type);
        } else {
            prm_idx = field_idx++;
        }
        auto &prm = fields->at(prm_idx);
        //todo if we support unnamed fields, change this
        if (!hasNamed) {
            names.insert(prm.name);
        }
        auto pt = getType(prm.type);
        auto arg = resolve(e.value);
        if (MethodResolver::isCompatible(arg, pt)) {
            auto f = format("field type is imcompatiple %s \n expected: %s got: %s", e.value->print().c_str(), pt.print().c_str(), arg.type.print().c_str());
            err(node, f);
        }
    }
    for (auto &p : *fields) {
        if (!names.contains(p.name)) {
            err(node, "field not covered: " + p.name);
        }
    }
    return res;
}

std::any Resolver::visitArrayAccess(ArrayAccess *node) {
    auto arr = getType(node->array);
    auto idx = getType(node->index);
    //todo unsigned
    if (idx.print() == "bool" || !idx.isPrim()) error("array index is not an integer");

    if (node->index2) {
        auto idx2 = getType(node->index2.get());
        if (idx2.print() == "bool" || !idx2.isPrim()) error("range end is not an integer");
        auto inner = arr.unwrap();
        if (inner.isSlice()) {
            return RType(clone(inner));
        } else if (inner.isArray()) {
            return RType(Type(Type::Slice, clone(*inner.scope)));
        } else if (arr.isPointer()) {
            //from raw pointer
            return RType(Type(Type::Slice, inner));
        } else {
            error("can't make slice out of " + arr.print());
        }
    }
    if (arr.isPointer()) {
        arr = getType(arr.scope.get());
    }
    if (arr.isArray()) {
        return resolve(arr.scope.get());
    }
    if (arr.isSlice()) {
        return resolve(arr.scope.get());
    }
    throw std::runtime_error("cant index: " + node->print());
}

Ptr<VarDecl> make_var(std::string name, Expression *rhs) {
    auto res = std::make_unique<VarDecl>();
    res->decl = new VarDeclExpr;
    Fragment f;
    f.name = name;
    f.rhs.reset(rhs);
    res->decl->list.push_back(std::move(f));
    return res;
}

std::unique_ptr<Method> generate_format(MethodCall *node, Resolver *r) {
    auto res = std::make_unique<Method>(r->unit.get());
    res->name = "format";
    res->type = Type("String");
    res->params.push_back(Param("s", Type("str")));
    res->body = std::make_unique<Block>();
    auto body = res->body.get();
    auto rhs = new MethodCall;
    rhs->is_static = true;
    rhs->scope.reset(new Type("Fmt"));
    rhs->name = "new";
    body->list.push_back(make_var("f", rhs));
    int i = 0;
    for (auto a : node->args) {
        auto arg_type = r->resolve(a);
        res->params.push_back(Param("p" + std::to_string(i), arg_type.type));
        i++;
    }
    body->list.push_back(makeRet(r->unit, makeFa("f", "buf")));
    return res;
}

std::any Resolver::visitMethodCall(MethodCall *mc) {
    if (is_ptr_get(mc)) {
        if (mc->args.size() != 2) {
            err("ptr access must have 2 args");
        }
        auto arg = getType(mc->args[0]);
        if (!arg.isPointer()) {
            err("ptr arg is not ptr " + mc->print());
        }
        auto idx = getType(mc->args[1]).print();
        if (idx == "i32" || idx == "i64" || idx == "u32" || idx == "u64" || idx == "i8" || idx == "i16") {
            return resolve(arg);
        } else {
            err("ptr access index is not integer");
        }
    }
    if (is_slice_get_ptr(mc)) {
        auto elem = getType(mc->scope.get());
        return RType(Type(Type::Pointer, *elem.scope.get()));
    }
    if (is_slice_get_len(mc)) {
        resolve(mc->scope.get());
        auto type = SLICE_LEN_BITS == 64 ? "i64" : "i32";
        return RType(Type(type));
    }
    if (is_array_get_len(mc)) {
        resolve(mc->scope.get());
        return RType(Type("i64"));
    }
    if (is_array_get_ptr(mc)) {
        auto arr_type = getType(mc->scope.get()).unwrap();
        return RType(Type(Type::Pointer, *arr_type.scope.get()));
    }
    auto sig = Signature::make(mc, this);
    if (mc->scope) {
        //rvalue
        if (dynamic_cast<MethodCall *>(mc->scope.get()) && getType(mc->scope.get()).isPrim()) {
            err(mc, "method scope is rvalue");
        }
        MethodResolver mr(this);
        auto res = mr.handleCallResult(sig);
        return res;
    }
    if (mc->name == "print") {
        return makeSimple("void");
    } else if (mc->name == "malloc") {
        Type in("i8");
        if (!mc->typeArgs.empty()) {
            in = getType(mc->typeArgs[0]);
        }
        return RType(Type(Type::Pointer, in));
    } else if (mc->name == "panic") {
        if (mc->args.empty()) {
            return RType(Type("void"));
        }
        auto lit = dynamic_cast<Literal *>(mc->args[0]);
        if (lit && lit->type == Literal::STR) {
            return RType(Type("void"));
        }
        throw std::runtime_error("invalid panic argument: " + mc->args[0]->print());
    } else if (mc->name == "format") {
        throw std::runtime_error("format todo");
        if (mc->args.empty()) {
            err("format expects format string");
        }
        auto lit = dynamic_cast<Literal *>(mc->args[0]);
        if (!lit || lit->type != Literal::STR) {
            err("invalid format argument: " + mc->args[0]->print());
        }
        for (auto a : mc->args) {
            auto arg_type = resolve(a);
        }
        if (mc->id == -1) {
            err(mc->print() + " must have id");
        }
        //cache generated method
        if (!format_methods.contains(mc->id)) {
            auto gm = generate_format(mc, this);
            //gm->accept(this);
            format_methods[mc->id] = std::move(gm);
        }
        //unit->items.push_back(std::move(gm));
        return RType(Type("String"));
    }
    MethodResolver mr(this);
    auto res = mr.handleCallResult(sig);
    //cache[id] = res;
    return res;
}

std::any Resolver::visitWhileStmt(WhileStmt *node) {
    if (!isCondition(node->expr.get(), this)) {
        error("while statement expr is not a bool");
    }
    inLoop++;
    newScope();
    node->body->accept(this);
    inLoop--;
    dropScope();
    return nullptr;
}

std::any Resolver::visitForStmt(ForStmt *node) {
    newScope();
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
    inLoop++;
    node->body->accept(this);
    inLoop--;
    dropScope();
    return nullptr;
}

std::any Resolver::visitContinueStmt(ContinueStmt *node) {
    if (inLoop == 0) {
        error("continue in outside of loop");
    }
    if (node->label) error("continue label");
    return nullptr;
}

std::any Resolver::visitBreakStmt(BreakStmt *node) {
    if (inLoop == 0) {
        err(node, "break in outside of loop");
    }
    if (node->label) error("break label");
    return nullptr;
}

std::any Resolver::visitArrayExpr(ArrayExpr *node) {
    if (node->isSized()) {
        auto elemType = getType(node->list[0]);
        return RType(Type(elemType, node->size.value()));
    }
    auto elemType = resolve(node->list[0]);
    for (int i = 1; i < node->list.size(); i++) {
        auto cur = resolve(node->list[i]);
        auto cmp = MethodResolver::isCompatible(cur, elemType.type);
        if (cmp.has_value()) {
            print(cmp.value());
            error("array element type mismatch, expecting: " + elemType.type.print() + " got: " + cur.type.print());
        }
    }
    return RType(Type(elemType.type, node->list.size()));
}