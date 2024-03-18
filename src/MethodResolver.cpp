#include "MethodResolver.h"
#include "TypeUtils.h"
#include "parser/Util.h"

std::string Signature::print() {
    std::string s;
    if (mc && mc->scope) {
        s += scope->type.print();
        s += "::";
    } else if (m && m->parent) {
        auto p = m->parent;
        if (p->isImpl()) {
            auto imp = (Impl *) p;
            s += imp->type.print();
            s += "::";
        }
    }
    if (mc) {
        s += mc->name;
    } else {
        s += m->name;
    }
    s += "(";
    int i = 0;
    for (auto &a : args) {
        if (i++ > 0) s += ",";
        s += a.print();
    }
    s += ")";
    return s;
}


Signature Signature::make(MethodCall *mc, Resolver *r) {
    Signature res;
    res.mc = mc;
    res.r = r;
    RType scp;
    if (mc->scope) {
        if (mc->print() == "self.expand()") {
            auto x = 66;
        }
        scp = r->resolve(mc->scope.get());
        //we need this to handle cases like Option::new(...)
        if (scp.targetDecl && scp.targetDecl->path != r->unit->path && !scp.targetDecl->isGeneric) {
            r->addUsed(scp.targetDecl);
        }
        if (scp.type.isPointer()) {
            res.scope = r->resolve(scp.type.unwrap());
        } else {
            res.scope = std::move(scp);
        }
        if (!dynamic_cast<Type *>(mc->scope.get())) {
            res.args.push_back(res.scope->type.toPtr());
        }
    }
    int i = 0;
    for (auto a : mc->args) {
        //cast to pointer
        auto type = r->getType(a);
        if (i == 0 && mc->scope && scp.trait && isStruct(type)) {
            type = Type(Type::Pointer, type);
        }
        res.args.push_back(type);
        i++;
    }
    return res;
}

Type handleSelf(const Type &type, Method *m) {
    if (type.print() != "Self") return type;
    auto imp = (Impl *) m->parent;
    return imp->type;
}

Signature Signature::make(Method *m, const std::map<std::string, Type> &map) {
    Signature res;
    res.m = m;
    if (m->parent && m->parent->isImpl()) {
        auto imp = (Impl *) m->parent;
        res.scope = RType(imp->type);
    }
    if (m->self) {
        res.args.push_back(*m->self->type);
    }
    for (auto &prm : m->params) {
        auto mapped = Generator::make(prm.type.value(), map);
        res.args.push_back(handleSelf(mapped, m));
    }
    res.ret = handleSelf(m->type, m);
    return res;
}


std::vector<Signature> MethodResolver::collect(Signature &sig) {
    std::vector<Signature> list;
    auto mc = sig.mc;
    if (mc->scope) {
        getMethods(sig, list, true);
    } else {
        findMethod(mc->name, list);
        for (auto &is : r->get_imports()) {
            auto resolver = Resolver::getResolver(is, r->root);
            resolver->init();
            MethodResolver mr(resolver.get());
            mr.findMethod(mc->name, list);
        }
    }
    return list;
}

void MethodResolver::findMethod(std::string &name, std::vector<Signature> &list) {
    for (auto &item : r->unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            if (m->name == name) {
                list.push_back(Signature::make(m, {}));
            }
        } else if (item->isExtern()) {
            auto ex = dynamic_cast<Extern *>(item.get());
            for (auto &m : ex->methods) {
                if (m.name == name) {
                    list.push_back(Signature::make(&m, {}));
                }
            }
        }
    }
    if (r->curImpl) {
        //sibling
        for (auto &m : r->curImpl->methods) {
            if (!m.self && m.name == name) {
                //todo map
                list.push_back(Signature::make(&m, {}));
            }
        }
    }
}

void get_type_map(const Type &type, Type &generic, std::map<std::string, Type> &map) {
    if (type.isArray() || type.isPointer() || type.isSlice() || type.isVoid() || type.scope) {
        throw std::runtime_error(type.print() + " " + generic.print());
    }
    if (type.isPrim() || generic.typeArgs.empty() /*|| !type.scope && type.typeArgs.empty()*/) {
        map[generic.print()] = type;
        return;
    }
    if (type.name != generic.name) {
        throw std::runtime_error(type.print() + " " + generic.print());
    }
    for (int i = 0; i < type.typeArgs.size(); ++i) {
        get_type_map(type.typeArgs[i], generic.typeArgs[i], map);
    }
}

std::map<std::string, Type> make_map(Signature &sig, Type &type) {
    auto type_plain = type;
    type_plain.typeArgs.clear();
    auto decl = sig.r->resolve(type_plain).targetDecl;
    std::map<std::string, Type> map;
    if (decl && decl->isGeneric && !type.typeArgs.empty()) {
        int i = 0;
        for (auto &tp : decl->type.typeArgs) {
            map[tp.print()] = type.typeArgs[i];
            ++i;
        }
    }
    return map;
}

void MethodResolver::getMethods(Signature &sig, std::vector<Signature> &list, bool imports) {
    auto &name = sig.mc->name;
    auto &scope = sig.scope.value();
    auto type = scope.type.unwrap();

    auto map = make_map(sig, type);

    for (auto &item : r->unit->items) {
        if (!item->isImpl()) {
            continue;
        }
        auto impl = dynamic_cast<Impl *>(item.get());
        if (scope.trait) {
            if (!impl->trait_name || impl->trait_name->name != type.name) continue;
            auto uw = sig.args[0].unwrap();
            if (impl->type.name != uw.name) continue;
        } else {
            if (impl->type.name != type.name) continue;
        }
        for (auto &m : impl->methods) {
            //todo generate if generic
            if (m.name != name) {
                continue;
            }
            auto ss = sig.mc->print();
            if (type.typeArgs.empty()) {
                list.push_back(Signature::make(&m, map));
            } else {
                std::map<std::string, Type> typeMap;
                for (int i = 0; i < m.typeArgs.size(); i++) {
                    auto &ta = m.typeArgs[i];
                    typeMap[ta.name] = type.typeArgs[i];
                }
                auto sig2 = Signature::make(&m, map);
                for (auto &a : sig2.args) {
                    a = Generator::make(a, typeMap);
                }
                list.push_back(std::move(sig2));
            }
        }
    }
    if (imports) {
        for (auto &is : r->get_imports()) {
            auto resolver = Resolver::getResolver(is, r->root);
            resolver->init();
            MethodResolver mr(resolver.get());
            mr.getMethods(sig, list, false);
        }
    }
}

void error(Resolver *r, const std::string &str) {
    error(printMethod(r->curMethod) + "\n" + str);
}


RType MethodResolver::handleCallResult(Signature &sig) {
    auto mc = sig.mc;
    auto list = collect(sig);
    if (list.empty()) {
        r->err(mc, "no such method: " + sig.mc->print() + " => " + sig.print());
    }
    //test candidates and get errors
    std::vector<Signature> real;
    std::map<Method *, std::string> errors;
    Signature *exact = nullptr;
    for (auto &sig2 : list) {
        auto cmp_res = isSame(sig, sig2);
        if (std::holds_alternative<std::string>(cmp_res)) {
            errors[sig2.m] = std::get<std::string>(cmp_res);
        } else {
            if (*std::get_if<bool>(&cmp_res)) {
                exact = &sig2;
            }
            real.push_back(sig2);
        }
    }
    if (real.empty()) {
        std::string s = "method: " + mc->print() + " not found from candidates:\n ";
        for (auto &[m, err] : errors) {
            s += printMethod(m) + " " + err + "\n";
        }
        r->err(mc, s);
    }
    if (real.size() > 1 && !exact) {
        std::string s;
        for (auto &m : real) {
            s += m.print() + "\n";
        }
        s = format("multiple candidates for %s=>%s\n%s", mc->print().c_str(), sig.print().c_str(), s.c_str());
        r->err(mc, s);
    }
    auto &sig2 = exact ? *exact : real[0];
    auto target = sig2.m;
    if (!target->isGeneric) {
        if (target->path != r->unit->path) {
            r->usedMethods.insert(target);
        }
        auto res = r->resolve(sig2.ret).clone();
        res.targetMethod = target;
        return res;
    }
    std::map<std::string, std::optional<Type>> typeMap;
    auto type_params = get_type_params(*target);
    //mark all as non inferred
    for (auto &ta : type_params) {
        typeMap[ta.name] = std::optional<Type>();
    }
    if (mc->scope) {
        //todo trait
        auto &scope = sig.scope->type;
        for (int i = 0; i < scope.typeArgs.size(); i++) {
            typeMap[type_params[i].name] = scope.typeArgs[i];
        }
        if (!mc->typeArgs.empty()) {
            error("todo");
        }
    } else {
        if (!mc->typeArgs.empty()) {
            //place specified type args in order
            for (int i = 0; i < mc->typeArgs.size(); i++) {
                typeMap[type_params[i].name] = r->getType(mc->typeArgs[i]);
            }
        }
    }
    //infer from args
    for (int i = 0; i < sig.args.size(); i++) {
        auto &arg_type = sig.args[i];
        auto &target_type = sig2.args[i];
        MethodResolver::infer(arg_type, target_type, typeMap);
    }
    std::map<std::string, Type> tmap;
    for (auto &[tp, stat] : typeMap) {
        if (!stat.has_value()) {
            error(r, "can't infer type parameter: " + tp);
        }
        tmap[tp] = stat.value();
    }
    target = generateMethod(tmap, target, sig);
    auto res = r->resolve(target->type).clone();
    res.targetMethod = target;
    return res;
}


void MethodResolver::infer(const Type &arg, const Type &prm, std::map<std::string, std::optional<Type>> &typeMap) {
    if (prm.isPointer()) {
        if (!arg.isPointer()) return;
        infer(*arg.scope.get(), *prm.scope.get(), typeMap);
        return;
    }//todo
    if (prm.typeArgs.empty()) {
        if (typeMap.contains(prm.name)) {
            auto it = typeMap.find(prm.name);
            if (!it->second) {
                it->second = arg;
            } else {
                auto m = MethodResolver::isCompatible(RType(arg), *it->second);
                if (m.has_value()) {
                    print(m.value());
                    error("type infer failed: " + it->second->print() + " vs " + arg.print());
                }
            }
        }
    } else {
        if (arg.typeArgs.size() != prm.typeArgs.size()) {
            error("type arg size mismatch, " + arg.print() + " = " + prm.print());
        }
        if (arg.name != prm.name) error("cant infer");
        for (int i = 0; i < arg.typeArgs.size(); i++) {
            auto &ta = arg.typeArgs[i];
            auto &tp = prm.typeArgs[i];
            infer(ta, tp, typeMap);
        }
    }
}

Method *MethodResolver::generateMethod(std::map<std::string, Type> &map, Method *m, Signature &sig) {
    for (auto gm : r->generatedMethods) {
        auto sig2 = Signature::make(gm, {});
        auto res = isSame(sig, sig2);
        if (std::holds_alternative<bool>(res)) {
            return gm;
        }
    }
    Generator gen(map);
    auto res = std::any_cast<Method *>(gen.visitMethod(m));
    res->used_path = r->unit->path;
    if (!m->parent || !m->parent->isImpl()) {
        r->generatedMethods.push_back(res);
        return res;
    }
    auto impl = dynamic_cast<Impl *>(m->parent);
    auto st = sig.scope->type;
    if (sig.scope->trait) {
        st = sig.args[0].unwrap();
    }
    //put full type, Box::new(...) -> Box<...>::new()
    if (sig.mc->is_static && !impl->type.typeArgs.empty()) {
        st.typeArgs.clear();
        for (auto &ta : impl->type.typeArgs) {
            auto resolved = map.at(ta.print());
            st.typeArgs.push_back(resolved);
        }
    }
    auto newImpl = new Impl(clone(st));
    res->parent = newImpl;
    r->generatedMethods.push_back(res);
    return res;
}

SigResult MethodResolver::isSame(Signature &sig, Signature &sig2) {
    auto mc = sig.mc;
    auto m = sig2.m;
    if (mc->name != m->name) return "not possible";
    if (!m->typeArgs.empty()) {
        if (!mc->typeArgs.empty() && mc->typeArgs.size() != m->typeArgs.size()) {
            return "type arg size mismatched";
        }
        if (!m->isGeneric) {
            //check if args are compatible with generic type params
            for (int i = 0; i < mc->typeArgs.size(); i++) {
                if (mc->typeArgs[i].print() != m->typeArgs[i].print()) {
                    return "type arg " + mc->typeArgs[i].print() + " not matched with " + m->typeArgs[i].print();
                }
            }
        }
    }
    if (m->parent && m->parent->isImpl() && mc->scope) {
        auto &scope = sig.scope->type;
        auto impl = dynamic_cast<Impl *>(m->parent);
        if (sig.scope->trait) {
            auto scp = sig.args[0].unwrap();
            if (scp.name != impl->type.name) {
                return format("not same impl %s vs %s", scp.name.c_str(), impl->type.name.c_str());
            }
        } else if (scope.name != impl->type.name) {
            return format("not same impl %s vs %s", scope.name.c_str(), impl->type.name.c_str());
        }
        if (impl->type_params.empty() && !impl->type.typeArgs.empty()) {
            //check they belong same impl
            for (int i = 0; i < scope.typeArgs.size(); i++) {
                if (scope.typeArgs[i].print() != impl->type.typeArgs[i].print()) return "not same impl";
            }
        }
    }
    //check if args are compatible with non generic params
    return checkArgs(sig, sig2);
}


SigResult MethodResolver::checkArgs(Signature &sig, Signature &sig2) {
    if (sig2.m->self && !sig.mc->scope) {
        return "member method called without scope";
    }
    if (sig.args.size() != sig2.args.size()) return "arg size mismatched";
    std::vector<Type> typeParams = get_type_params(*sig2.m);
    bool all_exact = true;
    for (int i = 0; i < sig.args.size(); i++) {
        auto &t1 = sig.args[i];
        auto &t2 = sig2.args[i];
        //todo if base method, skip self
        if (t1.print() != t2.print()) {
            all_exact = false;
        }
        if (isCompatible(RType(t1), t2, typeParams)) {
            return "arg type " + t1.print() + " is not compatible with param " + t2.print();
        }
    }
    return all_exact;
}

std::optional<std::string> MethodResolver::isCompatible(const RType &arg0, const Type &target, const std::vector<Type> &typeParams) {
    auto &arg = arg0.type;
    if (arg.print() == target.print()) return {};
    if (isGeneric2(target.print(), typeParams)) {
        return {};
    }
    if (arg.isPointer()) {
        auto elem = arg.scope.get();
        if (target.isPointer()) {
            //A* -> T* | A*
            return isCompatible(RType(*elem), *target.scope, typeParams);
        } else {
            //A* -> T
            if (isGeneric2(target.print(), typeParams)) {
                return {};
            }
            return "target is not ptr";
        }
    }
    if(target.isPointer()){
        return "arg is not ptr";
    }
    if (arg.isPointer() || arg.isSlice() || arg.isArray()) {
        if (arg.print() == target.print()) {
            return {};
        }
        if (arg.kind != target.kind) {
            return "";
        }
        if (hasGeneric(target, typeParams)) {
            return isCompatible(RType(*arg.scope), *target.scope, typeParams);
        }
        //return arg.print() + " is not compatible with " + target.print();
        return "";
    }
    if (!target.typeArgs.empty()) {
        if (arg.typeArgs.size() != target.typeArgs.size()) {
            return "type args size don't match";
        }
        for (int i = 0; i < arg.typeArgs.size(); ++i) {
            auto &ta = arg.typeArgs[i];
            auto &tp = target.typeArgs[i];
            auto res = isCompatible(RType(ta), tp, typeParams);
            if (res.has_value()) {
                return res;
            }
        }
        return {};
    }
    if (hasGeneric(target, typeParams)) {
        return isCompatible(RType(*arg.scope), *target.scope, typeParams);
    }
    //if (isGeneric(target, typeParams)) return {};
    if (!arg.isPrim()) {
        return "";
    }
    if (!target.isPrim()) return "target is not prim";
    if (arg.print() == "bool" || target.print() == "bool") return "target is not bool";
    if (arg0.value) {
        //autocast literal
        auto &v = arg0.value.value();
        if (v[0] == '-') {
            if (isUnsigned(target)) return v + " is signed but " + target.print() + " is unsigned";
            //check range
        } else {
            if (max_for(target) >= stoll(v)) {
                return {};
            } else {
                return v + " can't fit into " + target.print();
            }
        }
    }
    if (isUnsigned(target) && isSigned(arg)) {
        return "arg is signed but target is unsigned";
    }
    // auto cast to larger size
    if (sizeMap[arg.name] <= sizeMap[target.name]) {
        return {};
    } else {
        return "arg can't fit into target";
    }
}