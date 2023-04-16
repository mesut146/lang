#include "MethodResolver.h"
#include "TypeUtils.h"
#include "parser/Util.h"

std::string printSig(Signature &sig) {
    std::string s;
    if (sig.mc && sig.mc->scope) {
        s += sig.scope->type->print();
        s += "::";
    } else if (sig.m && sig.m->parent) {
        auto p = sig.m->parent;
        auto imp = (Impl *) p;
        s += imp->type->print();
        s += "::";
    }
    if (sig.mc)
        s += sig.mc->name;
    else
        s += sig.m->name;
    s += "(";
    int i = 0;
    for (auto &a : sig.args) {
        if (i++ > 0) s += ",";
        s += a->print();
    }
    s += ")";
    return s;
}

Signature Signature::make(MethodCall *mc, Resolver *r) {
    Signature res;
    res.mc = mc;
    if (mc->scope) {
        auto scp = r->resolve(mc->scope.get());
        if (scp.type->isPointer()) {
            res.scope = r->resolve(PointerType::unwrap(scp.type));
        } else {
            res.scope = std::move(scp);
        }
        if (!dynamic_cast<Type *>(mc->scope.get())) {
            res.args.push_back(makeSelf(res.scope->type));
        }
    }
    for (auto a : mc->args) {
        res.args.push_back(r->getType(a));
    }
    return res;
}

Type *handleSelf(Type *type, Method *m) {
    if (type->print() != "Self") return type;
    auto imp = (Impl *) m->parent;
    return imp->type;
}

Signature Signature::make(Method *m, Resolver *r) {
    Signature res;
    res.m = m;
    if (m->self) {
        res.args.push_back(m->self->type.get());
    }
    for (auto &prm : m->params) {
        res.args.push_back(handleSelf(prm.type.get(), m));
    }
    res.ret = handleSelf(m->type.get(), m);
    return res;
}


std::vector<Signature> MethodResolver::collect(Signature &sig) {
    std::vector<Signature> list;
    auto mc = sig.mc;
    if (mc->scope) {
        getMethods(sig, list, true);
    } else {
        findMethod(mc->name, list);
        for (auto &is : r->unit->imports) {
            auto resolver = Resolver::getResolver(is, r->root);
            resolver->init();
            MethodResolver mr(resolver.get());
            mr.findMethod(mc->name, list);
        }
    }
    return list;
}

bool isGeneric(Type *type, std::vector<Type *> &typeParams) {
    if (type->scope) error("isGeneric::scope");
    if (type->typeArgs.empty()) {
        for (auto &t : typeParams) {
            if (t->print() == type->print()) return true;
        }
    } else {
        for (auto ta : type->typeArgs) {
            if (isGeneric(ta, typeParams)) return true;
        }
    }
    return false;
}

void MethodResolver::findMethod(std::string &name, std::vector<Signature> &list) {
    for (auto &item : r->unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            if (m->name == name) {
                list.push_back(Signature::make(m, r));
            }
        } else if (item->isExtern()) {
            auto ex = dynamic_cast<Extern *>(item.get());
            for (auto &m : ex->methods) {
                if (m.name == name) { list.push_back(Signature::make(&m, r)); }
            }
        }
    }
    if (r->curImpl) {
        //sibling
        for (auto &m : r->curImpl->methods) {
            if (!m.self && m.name == name) {
                list.push_back(Signature::make(&m, r));
            }
        }
    }
}

void MethodResolver::getMethods(Signature& sig, std::vector<Signature> &list, bool imports) {
    auto &name = sig.mc->name;
    auto& rt = sig.scope.value();
    auto type = rt.type;
    type = PointerType::unwrap(type);
    if (rt.targetDecl && rt.targetDecl->base) {
        auto rr = Resolver::getResolver(rt.unit->path, r->root);
        auto base = rr->resolve(rt.targetDecl->base.get());
        //getMethods(base, name, list, false);
    }
    for (auto &item : r->unit->items) {
        if (!item->isImpl()) {
            continue;
        }
        auto impl = dynamic_cast<Impl *>(item.get());
        if(rt.trait){
            if (impl->trait_name->name != type->name) continue;
            if (impl->type->name!=sig.args[0]->name) continue;
        }else{
            if (impl->type->name != type->name) continue;
        }
        for (auto &m : impl->methods) {
            //todo generate if generic
            if (m.name != name) {
                continue;
            }
            if (type->typeArgs.empty()) {
                list.push_back(Signature::make(&m, r));
            } else {
                std::map<std::string, Type *> typeMap;
                for (int i = 0; i < m.typeArgs.size(); i++) {
                    auto ta = m.typeArgs[i];
                    typeMap[ta->name] = type->typeArgs[i];
                }
                Generator gen(typeMap);
                auto sig = Signature::make(&m, r);
                for (auto &a : sig.args) {
                    a = (Type *) std::any_cast<Expression *>(a->accept(&gen));
                }
                list.push_back(std::move(sig));
            }
        }
    }
    if (imports) {
        for (auto &is : r->unit->imports) {
            auto resolver = Resolver::getResolver(is, r->root);
            resolver->init();
            MethodResolver mr(resolver.get());
            mr.getMethods(sig, list, false);
        }
    }
}

void MethodResolver::infer(Type *arg, Type *prm, std::map<std::string, Type *> &typeMap) {
    auto it = typeMap.find(prm->name);
    if (prm->typeArgs.empty()) {
        if (it != typeMap.end()) {
            if (it->second == nullptr) {
                it->second = arg;
            } else {
                std::vector<Type *> tmp;
                if (!MethodResolver::isCompatible(it->second, arg, tmp)) {
                    error("type infer failed: " + it->second->print() + " vs " + arg->print());
                }
            }
        }
    } else {
        if (arg->typeArgs.size() != prm->typeArgs.size()) {
            error("type arg size mismatch, " + arg->print() + " = " + prm->print());
        }
        if (arg->name != prm->name) error("cant infer");
        for (int i = 0; i < arg->typeArgs.size(); i++) {
            auto ta = arg->typeArgs[i];
            auto tp = prm->typeArgs[i];
            infer(ta, tp, typeMap);
        }
    }
}


RType MethodResolver::handleCallResult(Signature &sig) {
    auto mc = sig.mc;
    auto list = collect(sig);
    if (list.empty()) {
        error("no such method: " + sig.mc->print() + " => " + printSig(sig));
    }
    std::vector<Signature> real;
    std::map<Method *, std::string> errors;
    for (auto &sig2 : list) {
        auto msg = isSame(sig, sig2);
        if (!msg) {
            real.push_back(std::move(sig2));
        } else {
            errors[sig2.m] = msg.value();
        }
    }
    if (real.empty()) {
        std::string s = "method: " + mc->print() + " not found from candidates:\n ";
        for (auto &[m, err] : errors) {
            s += printMethod(m) + " " + err + "\n";
        }
        error(s);
    }
    //remove base method if derived exist
    if (mc->scope && real.size() == 2) {
        auto &m1 = real[0];
        auto &m2 = real[1];
        if (m1.m->self->type->print() == sig.scope->type->print()) {
            //m1 is derived
            real.erase(real.begin() + 1);
        } else {
            //m2 is derived
            real.erase(real.begin());
        }
    }
    if (real.size() > 1) {
        std::string s;
        for (auto &m : real) {
            s += printSig(m) + "\n";
        }
        error("method:  " + mc->print() + "\n" + printSig(sig) + " has " +
              std::to_string(real.size()) + " candidates;\n" + s);
    }
    auto &sig2 = real[0];
    auto target = sig2.m;
    RType res;
    if (!target->isGeneric) {
        if (target->unit->path != r->unit->path) {
            r->usedMethods.insert(target);
        }
        res = clone(r->resolve(sig2.ret));
        res.targetMethod = target;
        return res;
    }
    std::map<std::string, Type *> typeMap;
    if (mc->typeArgs.empty()) {
        //infer
        for (auto ta : target->typeArgs) {
            typeMap[ta->name] = nullptr;
        }
        if (mc->scope) {
            auto scope = sig.scope->type;
            for (int i = 0; i < scope->typeArgs.size(); i++) {
                typeMap[target->typeArgs[i]->name] = scope->typeArgs[i];
            }
        }
        for (int i = 0; i < sig.args.size(); i++) {
            auto arg_type = sig.args[i];
            auto target_type = sig2.args[i];
            MethodResolver::infer(arg_type, target_type, typeMap);
        }
        for (auto &i : typeMap) {
            if (i.second == nullptr) {
                error("can't infer type parameter: " + i.first);
            }
        }
    } else {
        if (mc->typeArgs.size() < target->typeArgs.size()) {
            error("not enough type args: " + mc->print());
        }
        //place specified type args
        for (int i = 0; i < mc->typeArgs.size(); i++) {
            auto argt = r->resolve(mc->typeArgs[i]);
            typeMap[target->typeArgs[i]->name] = argt.type;
        }
    }
    target = generateMethod(typeMap, target, sig);
    res = clone(r->resolve(target->type.get()));
    res.targetMethod = target;
    return res;
}

Method *MethodResolver::generateMethod(std::map<std::string, Type *> &map, Method *m, Signature &sig) {
    auto mc = sig.mc;
    for (auto &gm : r->generatedMethods) {
        auto sig2 = Signature::make(gm, r);
        if (!isSame(sig, sig2).has_value()) {
            return gm;
        }
    }
    Generator gen(map);
    auto res = std::any_cast<Method *>(gen.visitMethod(m));
    if (m->parent && m->parent->isImpl()) {
        auto impl = dynamic_cast<Impl *>(m->parent);
        auto newImpl = new Impl(clone(sig.scope->type));
        res->parent = newImpl;
    }
    r->generatedMethods.push_back(res);
    return res;
}

bool MethodResolver::isCompatible(Type *arg, Type *target, std::vector<Type *> &typeParams) {
    if (isGeneric(target, typeParams)) return true;
    if (arg->print() == target->print()) return true;
    if (arg->isPointer()) {
        if (!target->isPointer()) return false;
        auto p1 = dynamic_cast<PointerType *>(arg);
        auto p2 = dynamic_cast<PointerType *>(target);
        return isCompatible(p1->type, p2->type, typeParams);
    }
    if (arg->isSlice()) {
        if (!target->isSlice()) return false;
        auto p1 = dynamic_cast<SliceType *>(arg);
        auto p2 = dynamic_cast<SliceType *>(target);
        return isCompatible(p1->type, p2->type, typeParams);
    }
    if (arg->isArray()) {
        if (!target->isArray()) return false;
        auto p1 = dynamic_cast<ArrayType *>(arg);
        auto p2 = dynamic_cast<ArrayType *>(target);
        return isCompatible(p1->type, p2->type, typeParams);
    }
    if (arg->isPrim()) {
        if (!target->isPrim()) return false;
        if (arg->print() == "bool" || target->print() == "bool") return false;
        // auto cast to larger size
        return sizeMap[arg->name] <= sizeMap[target->name];
    }
    return false;
}

std::optional<std::string> MethodResolver::isSame(Signature &sig, Signature &sig2) {
    auto mc = sig.mc;
    auto m = sig2.m;
    if (mc->name != m->name) return "";
    if (!m->typeArgs.empty()) {
        if (!mc->typeArgs.empty()) {
            //size mismatch
            if (mc->typeArgs.size() != m->typeArgs.size()) return "type arg size mismatched";
        }
        if (!m->isGeneric) {
            //check if args are compatible with generic type params
            for (int i = 0; i < mc->typeArgs.size(); i++) {
                if (mc->typeArgs[i]->print() != m->typeArgs[i]->print()) {
                    return "type arg " + mc->typeArgs[i]->print() + " not matched with " + m->typeArgs[i]->print();
                }
            }
        }
    }
    if (m->parent && m->parent->isImpl() && mc->scope) {
        auto impl = dynamic_cast<Impl *>(m->parent);
        if (!impl->isGeneric && !impl->type->typeArgs.empty()) {
            auto scope = sig.scope->type;
            //check they belong same impl
            for (int i = 0; i < scope->typeArgs.size(); i++) {
                if (scope->typeArgs[i]->print() != impl->type->typeArgs[i]->print()) return "not same impl";
            }
        }
    }
    //check if args are compatible with non generic params
    return checkArgs(sig, sig2);
}


std::optional<std::string> MethodResolver::checkArgs(Signature &sig, Signature &sig2) {
    if (sig2.m->self && !sig.mc->scope) {
        return "member method called without scope";
    }
    if (sig.args.size() != sig2.args.size()) return "arg size mismatched";
    auto typeParams = sig2.m->isGeneric ? sig2.m->typeArgs : std::vector<Type *>();
    for (int i = 0; i < sig.args.size(); i++) {
        auto t1 = sig.args[i];
        auto t2 = sig2.args[i];
        if (sig2.m->self && i == 0) {
            //t1 = PointerType::unwrap(t1);
            //if base method, skip self
            auto imp = (Impl *) sig2.m->parent;
            if (imp->type->name != sig.scope->type->name) {
                continue;
            }
        }
        if (!isCompatible(t1, t2, typeParams)) {
            return "arg type " + t1->print() + " is not compatible with param " + t2->print();
        }
    }
    return {};
}
