#include "Resolver.h"
#include "MethodResolver.h"
#include "Ownership.h"
#include "TypeUtils.h"
#include "parser/Parser.h"
#include "parser/Util.h"
#include <any>
#include <list>
#include <memory>
#include <unordered_set>


bool isCondition(Expression *e, Resolver *r) {
    return r->getType(e).print() == "bool";
}

bool isComp(const std::string &op) {
    return op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=";
}

template<class T>
bool iof(Expression *e) {
    return dynamic_cast<T>(e) != nullptr;
}

RType RType::clone() {
    auto res = RType(type);
    res.unit = unit;
    res.targetDecl = targetDecl;
    res.targetMethod = targetMethod;
    if (vh) {
        res.vh = vh.value();
    }
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

// void printLine(Resolver *r, Node *n) {
//     std::cout << r->unit->path << ":" << n->line << std::endl;
//     if (r->curMethod) {
//         std::cout << "in " + printMethod(r->curMethod) << std::endl;
//     }
// }

void Resolver::err(Node *e, const std::string &msg) {
    std::string s;
    if (curMethod) {
        s += curMethod->path + ":" + std::to_string(e->line) + "\n";
        s += "in " + printMethod(curMethod) + "\n";
    } else {
        s += unit->path + ":" + std::to_string(e->line) + "\n";
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
        std::string s = format("%s\nin %s\n%s", curMethod->path.c_str(), printMethod(curMethod).c_str(), msg.c_str());
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
            //print("in " + std::to_string(prev.line));
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

// std::string Resolver::getId(Expression *e) {
//     auto res = e->accept(&idgen);
//     if (res.has_value()) {
//         return std::any_cast<std::string>(res);
//     }
//     throw std::runtime_error("id: " + e->print());
// }

std::unordered_map<std::string, std::shared_ptr<Resolver>> Resolver::resolverMap;
std::vector<std::string> Resolver::prelude = {"Box", "List", "str", "String", "Option", "ops", "libc"};

Resolver::Resolver(std::shared_ptr<Unit> unit, const std::string &root) : unit(unit), root(root) {
}

void Resolver::init_prelude() {
    for (auto &pre : prelude) {
        getResolver(Config::root + "/std/" + pre + ".x", Config::root);
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
        auto r = getResolver(curMethod->path, root);
        for (auto &is : r->unit->imports) {
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

void Resolver::addScope(std::string &name, const Type &type, bool prm, int line, int id) {
    if (scopes.empty()) {
        throw std::runtime_error("no scope for " + name + " line: " + std::to_string(line));
    }
    for (auto &scope : this->scopes) {
        if (scope.find(name)) {
            print("in " + unit->path + ":" + std::to_string(line));
            throw std::runtime_error("variable " + name + " already declared in the same scope");
        }
    }
    scopes.back().add(VarHolder(name, type, prm, id));
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
            auto err_opt = MethodResolver::isCompatible(RType(rhs.type), type);
            if (err_opt.is_err()) {
                std::string msg = "variable type mismatch '" + g.name + "'\n";
                msg += "expected: " + type.print() + " got " + rhs.type.print();
                msg += "\n" + err_opt.err;
                err(&g, msg);
            }
        }
        addScope(g.name, rhs.type, false, 0, g.id);
    }
    for (auto &item : unit->items) {
        item->accept(this);
    }
    for (int i = 0; i < generated_impl.size(); ++i) {
        auto &imp = generated_impl.at(i);
        imp->accept(this);
        auto m = &imp->methods.at(0);
        auto mangled = mangle(m);
        bool has = false;
        for (auto prev : generatedMethods) {
            if (mangled == mangle(prev)) {
                has = true;
                break;
            }
        }
        if (!has) {
            generatedMethods.push_back(m);
        }
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
        // if (!gm->parent2.is_none()) {
        //     curImpl = dynamic_cast<Impl *>(gm->parent);
        // }
        gm->accept(this);
        curImpl = nullptr;
    }
}

void initSelf(Unit *unit) {
    for (auto &item : unit->items) {
        if (!item->isImpl()) {
            continue;
        }
        auto imp = (Impl *) item.get();
        init_self_type(imp);
    }
}


void init_impl(Impl *impl, Resolver *r) {
    if (impl->type_params.empty()) {
        return;
    }
    for (auto &m : impl->methods) {
        m.isGeneric = true;
    }
}

bool is_drop_impl(BaseDecl *bd, Impl *imp) {
    if (!imp->trait_name.has_value() || imp->trait_name->print() != "Drop") return false;
    if (bd->isGeneric) {
        if (!imp->type_params.empty()) {//generic impl
            return bd->type.name == imp->type.name;
        } else {//full impl
            //different impl of type param
            return false;
        }
        return bd->type.name == bd->type.name;
    } else {                           //full type
        if (imp->type_params.empty()) {//full impl
            return bd->type.print() == imp->type.print();
        } else {//generic impl
            return bd->type.name == imp->type.name;
        }
    }

    return false;
}

//check if Drop trait implemented for this type
bool has_drop_impl(BaseDecl *bd, Resolver *r) {
    if (bd->path != r->unit->path) {
        //need own resolver
        r = r->getResolver(bd->path, r->root).get();
        r->init();
    }
    for (auto &it : r->unit->items) {
        if (!it->isImpl()) {
            continue;
        }
        auto imp = dynamic_cast<Impl *>(it.get());
        if (is_drop_impl(bd, imp)) {
            return true;
        }
    }
    for (auto &imp : r->generated_impl) {
        if (is_drop_impl(bd, imp.get())) {
            return true;
        }
    }
    return false;
}

void Resolver::init() {
    if (is_init) return;
    is_init = true;
    for (auto &item : unit->items) {
        if (item->isClass() || item->isEnum()) {
            auto bd = dynamic_cast<BaseDecl *>(item.get());
            auto res = makeSimple(bd->getName());
            res.unit = unit.get();
            res.targetDecl = bd;
            addType(bd->getName(), res);
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
    //derives
    std::vector<std::unique_ptr<Impl>> newItems;
    for (auto &item : unit->items) {
        if (!item->isClass() && !item->isEnum()) continue;
        auto bd = dynamic_cast<BaseDecl *>(item.get());
        bool has_derive_drop = false;
        for (auto &der : bd->derives) {
            if (der.print() == "Drop") {
                if (!bd->isGeneric) {
                    newItems.push_back(derive_drop(bd));
                    init_impl(newItems.back().get(), this);
                    has_derive_drop = true;
                } else {
                    //err("generic drop");
                    newItems.push_back(derive_drop(bd));
                    init_impl(newItems.back().get(), this);
                    has_derive_drop = true;
                }
            } else if (der.print() == "Debug") {
                newItems.push_back(derive_debug(bd));
                init_impl(newItems.back().get(), this);
            }
        }
        DropHelper helper(this);
        //auto impl drop
        if (!has_derive_drop && !has_drop_impl(bd, this) && (bd->isGeneric || helper.isDrop(bd))) {
            newItems.push_back(derive_drop(bd));
            init_impl(newItems.back().get(), this);
        }
    }
    for (auto &ni : newItems) {
        unit->items.push_back(std::move(ni));
    }
    initSelf(unit.get());
}

RType Resolver::resolve(Expression *expr) {
    //print("resolve " + expr->print());
    if (dynamic_cast<Type *>(expr)) {
        return std::any_cast<RType>(expr->accept(this));
    }
    if (expr->id == -1) {
        err(expr, "id=-1");
    }
    if (cache.contains(expr->id)) {
        return cache[expr->id];
    }
    /*std::cout << unit->path << ":"<<expr->line<<"\n";
    std::cout << printMethod(curMethod) << ", ";
    std::cout << expr->id << ", " << expr->print() << std::endl;*/
    auto res = std::any_cast<RType>(expr->accept(this));
    cache[expr->id] = res;
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
                    err(node, "cyclic type " + ep.type.print());
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
            err(node, "cyclic type " + fd.type.print());
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
    if (m.self.has_value()) {
        s += "_";
        s += parent.print() + "*";
    }
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
        err(m, "main method's return type must be 'void' or 'i32'");
    }
    curMethod = m;
    //ownerMap.insert({mangle(m), Ownership{}});
    //curOwner = &ownerMap.at(mangle(m));

    //print("visitMethod "+ printMethod(m));
    if (m->isVirtual && !m->self) {
        err(m, "virtual method must have self parameter");
    }
    //todo check if both virtual and override
    auto orr = isOverride(m);
    if (orr) {
        //print(printMethod(m) + " overrides " + printMethod(orr));
        overrideMap[m] = orr;
    }
    auto res = resolve(m->type).clone();
    res.targetMethod = m;
    max_scope = 0;
    newScope();
    if (m->self) {
        if (!m->self->type) err(m, "self type is not set");
        addScope(m->self->name, *m->self->type, true, m->line, m->self->id);
        m->self->accept(this);
    }
    for (auto &prm : m->params) {
        addScope(prm.name, *prm.type, true, m->line, prm.id);
        prm.accept(this);
    }
    if (m->body) {
        m->body->accept(this);
        //todo check unreachable
        auto exit = Exit::get_exit_type(m->body.get());
        if (!m->type.isVoid() && !exit.is_exit()) {
            err(m, "non void function must return a value");
        }
    }
    dropScope();
    curMethod = nullptr;
    //curOwner = nullptr;
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
    if (err_opt.is_err()) {
        std::string msg = "variable type mismatch '" + f->name + "'\n";
        msg += "expected: " + res.type.print() + " got " + rhs.type.print();
        msg += "\n" + err_opt.err;
        err(f, msg);
    }
    return res;
}

std::any Resolver::visitVarDeclExpr(VarDeclExpr *vd) {
    for (auto &f : vd->list) {
        auto rt = std::any_cast<RType>(f.accept(this));
        addScope(f.name, rt.type, false, f.line, f.id);
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
        res->path = decl->path;
        res->type = clone(type);
        res->attr = decl->attr;
        res->derives = decl->derives;
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
        res->path = decl->path;
        res->type = clone(type);
        res->attr = decl->attr;
        res->derives = decl->derives;
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
    if (str == "Self" && !curMethod->parent.is_none()) {
        return resolve(curMethod->parent.type.value());
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
                    if (res.targetDecl && !res.targetDecl->isGeneric) {
                        addUsed(res.targetDecl);

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

bool is_same_impl(Impl *a, Impl *b) {
    if (a->trait_name.has_value()) {
        if (!b->trait_name.has_value()) {
            return false;
        }
        if (a->trait_name->print() != b->trait_name->print()) {
            return false;
        }
    } else {
        if (b->trait_name.has_value()) {
            return false;
        }
    }
    return a->type.print() == b->type.print();
}

//find generated or user provided drop method
Method *find_drop_method(BaseDecl *bd, Resolver *r0) {
    auto r = r0->getResolver(bd->path, r0->root);
    r->init();
    for (auto &it : r->unit->items) {
        if (!it->isImpl()) continue;
        auto impl = dynamic_cast<Impl *>(it.get());
        if (!impl->trait_name.has_value() || impl->trait_name->print() != "Drop") continue;
        if (bd->type.print() == impl->type.print()) {
            return &impl->methods.at(0);
        }
        if (bd->type.typeArgs.empty()) {//non generic
            if (bd->type.print() == impl->type.print()) {
                return &impl->methods.at(0);
            }
        } else {//generic struct & generic impl
            if (bd->type.name == impl->type.name) {
                return &impl->methods.at(0);
            }
        }
    }
    throw std::runtime_error("find_drop_method " + bd->type.print());
    //return nullptr;
}

void Resolver::addUsed(BaseDecl *bd) {
    if (bd->path == unit->path && bd->type.typeArgs.empty()) return;
    for (auto prev : usedTypes) {
        if (prev->type.print() == bd->type.print()) return;
    }
    usedTypes.push_back(bd);
    if (bd->type.print() == "Map<String, Type>") {
        int xxx = 555;
    }
    //find drop impl and generate drop method
    //generate drop impl
    DropHelper helper(this);
    if (!bd->type.typeArgs.empty() && helper.isDrop(bd) /*&& !has_drop_impl(bd, this)*/) {
        auto dropm = find_drop_method(bd, this);
        if (dropm->isGeneric) {
            std::map<std::string, Type> map;
            for (int i = 0; i < dropm->parent.type_params.size(); ++i) {
                map[dropm->parent.type_params[i].name] = bd->type.typeArgs.at(i);
            }
            Generator gen(map);
            auto genm = std::any_cast<Method *>(gen.visitMethod(dropm));
            genm->parent.type_params.clear();
            genm->parent.type = bd->type;
            generatedMethods.push_back(genm);
            drop_methods[bd->type.print()] = genm;
        } else {
            drop_methods[bd->type.print()] = dropm;
        }
    }
    auto sd = dynamic_cast<StructDecl *>(bd);
    if (sd != nullptr) {
        for (auto &fd : sd->fields) {
            auto rt = resolve(fd.type);
            if (rt.targetDecl != nullptr) {
                addUsed(rt.targetDecl);
            }
        }
    } else {
        auto ed = dynamic_cast<EnumDecl *>(bd);
        for (auto &ev : ed->variants) {
            for (auto &fd : ev.fields) {
                auto rt = resolve(fd.type);
                if (rt.targetDecl != nullptr) {
                    addUsed(rt.targetDecl);
                }
            }
        }
    }
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

bool has_pointer(const Type &ty, Resolver *r) {
    if (ty.isPointer()) return false;
    auto rt = r->resolve(ty);
    if (rt.targetDecl == nullptr) return false;
    auto bd = rt.targetDecl;
    if (bd->base && has_pointer(bd->base.value(), r)) {
        return true;
    }
    if (bd->isEnum()) {
        auto en = dynamic_cast<EnumDecl *>(bd);
        for (auto &ev : en->variants) {
            for (auto &f : ev.fields) {
                if (f.type.isPointer() || has_pointer(f.type, r)) {
                    return true;
                }
            }
        }
    } else {
        auto td = dynamic_cast<StructDecl *>(bd);
        for (auto &fd : td->fields) {
            if (fd.type.isPointer() || has_pointer(fd.type, r)) {
                return true;
            }
        }
    }
    return false;
}

RType visit_deref(DerefExpr *node, Resolver *r, bool check) {
    auto rt = r->resolve(node->expr.get());
    auto &inner = rt.type;
    if (!inner.isPointer()) {
        error("deref expr is not pointer: " + node->expr->print());
    }
    if (check && has_pointer(*inner.scope.get(), r)) {
        auto mc = dynamic_cast<MethodCall *>(node->expr.get());
        if (!mc || !is_ptr_get(mc)) {
            //r->err(node, "unsafe deref");
            //printLine(r, node);
            //std::cout << "unsafe " << node->print() << std::endl;
        }
    }
    auto res = rt.clone();
    res.type = *inner.scope.get();
    return res;
}

bool is_var(Expression *e) {
    auto sn = dynamic_cast<SimpleName *>(e);
    if (sn) return true;
    auto fa = dynamic_cast<FieldAccess *>(e);
    if (fa) return is_var(fa->scope);
    /*auto de = dynamic_cast<DerefExpr *>(e);
    if (de) return is_var(de->expr.get());*/
    return false;
}

std::any Resolver::visitAssign(Assign *node) {
    RType t1;
    auto de = dynamic_cast<DerefExpr *>(node->left);
    if (de) {
        t1 = visit_deref(de, this, false);
    } else {
        t1 = resolve(node->left);
    }
    auto t2 = resolve(node->right);
    if (MethodResolver::isCompatible(t2, t1.type).is_err()) {
        err(node, "cannot assign " + t1.type.print() + " vs " + t2.type.print());
    }
    if (has_pointer(t1.type, this) && is_var(node->left)) {
        //err(node, "destroy left");
    }
    //curOwner->doMove(node->left, node->right);
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
    for (auto &is : get_imports()) {
        auto res = getResolver(is, root);
        for (auto &glob : res->unit->globals) {
            if (glob.name == node->name) {
                return resolve(glob.expr);
            }
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
    return visit_deref(node, this, true);
}

std::any Resolver::visitAssertStmt(AssertStmt *node) {
    if (!isCondition(node->expr.get(), this)) {
        err(node, "assert expr is not bool");
    }
    return nullptr;
}

std::any Resolver::visitIfLetStmt(IfLetStmt *node) {
    auto rt = resolve(node->type);
    if (!rt.targetDecl->isEnum()) {
        err(node, "if let type is not enum: " + node->type.print());
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
        auto ty = variant.fields[i].type;
        if (arg.ptr) {
            ty = Type(Type::Pointer, ty);
        } else {
            //todo
            /*if (rhs.type.isPointer()) {
                err(node, "if let arg non-ptr but rhs is ptr, " + arg.name);
            }*/
        }
        addScope(arg.name, ty, false, node->line, arg.id);
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
        if (i > 0) {
            auto prev_exit = Exit::get_exit_type(node->list[i - 1].get());
            if (prev_exit.is_jump()) {
                err(st.get(), "unreachable code");
            }
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
        if (MethodResolver::isCompatible(type, mtype).is_err()) {
            //err(node, );
            err(node, "method " + printMethod(curMethod) + " expects '" + mtype.print() + " but returned '" + type.type.print() + "' => ");
        }
        //curOwner->doMoveReturn(node->expr.get());
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
        //todo generic enum
        if (!ed->isGeneric && !ed->type.typeArgs.empty()) {
            addUsed(ed);
        }
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
        if (MethodResolver::isCompatible(arg, pt).is_err()) {
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

void validate_printf(MethodCall *mc, Resolver *r) {
    //check fmt literal
    auto fmt = mc->args.at(0);
    if (!isStrLit(fmt)) {
        r->err(mc, "format string is not a string literal");
    }
    //check rest
    for (int i = 1; i < mc->args.size(); ++i) {
        auto arg = r->getType(mc->args.at(i));
        if (!(arg.isPrim() || arg.print() == "i8*" || arg.print() == "u8*")) {
            r->err(mc, "format arg is invalid");
        }
    }
}

std::any Resolver::visitMethodCall(MethodCall *mc) {
    if (is_std_parent_name(mc)) {
        return RType(Type("str"));
    }
    if (is_std_no_drop(mc)) {
        auto rt = resolve(mc->args[0]);
        return RType(Type("void"));
    }
    if (is_drop_call(mc)) {
        auto arg = resolve(mc->args.at(0));
        if (arg.type.isPointer() && arg.type.scope && arg.type.scope->isPointer()) {
            return RType(Type("void"));
        }
        DropHelper helper(this);
        if (!helper.isDropType(arg)) {
            return RType(Type("void"));
        }
    }
    if (is_std_size(mc)) {
        if (!mc->args.empty()) {
            resolve(mc->args[0]);
        } else {
            if (mc->typeArgs.size() != 1) {
                err(mc, "std::size requires one type argument");
            }
            mc->typeArgs[0].accept(this);
        }
        return RType(Type("i64"));
    }
    if (is_std_is_ptr(mc)) {
        if (mc->typeArgs.size() != 1) {
            err(mc, "std::is_ptr requires one type argument");
        }
        mc->typeArgs[0].accept(this);
        return RType(Type("bool"));
    }
    if (is_ptr_get(mc)) {
        if (mc->args.size() != 2) {
            err(mc, "ptr access must have 2 args");
        }
        auto arg = getType(mc->args[0]);
        if (!arg.isPointer()) {
            err(mc, "ptr arg is not ptr ");
        }
        auto idx = getType(mc->args[1]).print();
        if (idx == "i32" || idx == "i64" || idx == "u32" || idx == "u64" || idx == "i8" || idx == "i16") {
            return resolve(arg);
        } else {
            err(mc, "ptr access index is not integer");
        }
    }
    if (is_ptr_copy(mc)) {
        if (mc->args.size() != 3) {
            err(mc, "ptr copy must have 3 args");
        }
        //ptr::copy(src_ptr, src_idx, elem)
        auto ptr_type = getType(mc->args.at(0));
        auto idx_type = getType(mc->args.at(1));
        auto elem_type = getType(mc->args.at(2));
        if (!ptr_type.isPointer()) {
            err(mc, "ptr arg is not ptr ");
        }
        if (idx_type.print() != "i32" && idx_type.print() != "i64" && idx_type.print() != "u32" && idx_type.print() != "u64" && idx_type.print() != "i8" && idx_type.print() != "i16") {
            err(mc, "ptr access index is not integer");
        }
        if (elem_type.print() != ptr_type.scope->print()) {
            err(mc, "ptr elem type dont match val type");
        }
        return RType(Type("void"));
    }
    if (is_ptr_deref(mc)) {
        //unsafe deref
        auto rt = getType(mc->args.at(0));
        if (!rt.isPointer()) {
            err(mc, "ptr arg is not ptr ");
        }
        return resolve(rt.scope.get());
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
    if (mc->name == "malloc") {
        for (auto arg : mc->args) {
            resolve(arg);
        }
        Type in("i8");
        if (!mc->typeArgs.empty()) {
            in = getType(mc->typeArgs[0]);
        }
        return RType(Type(Type::Pointer, in));
    } else if (is_format(mc)) {
        generate_format(mc, this);
        return RType(Type("String"));
    } else if (is_printf(mc)) {
        validate_printf(mc, this);
        return RType(Type("void"));
    } else if (is_print(mc)) {
        generate_format(mc, this);
        return RType(Type("void"));
    } else if (is_panic(mc)) {
        generate_format(mc, this);
        return RType(Type("void"));
    }
    auto sig = Signature::make(mc, this);
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
        if (cmp.is_err()) {
            print(cmp.err);
            error("array element type mismatch, expecting: " + elemType.type.print() + " got: " + cur.type.print());
        }
    }
    return RType(Type(elemType.type, node->list.size()));
}