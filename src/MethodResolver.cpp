#include "MethodResolver.h"

void Resolver::findMethod(MethodCall *mc, std::vector<Method *> &list, std::vector<Method *> &generics) {
    // for (auto m : generatedMethods) {
    //     if (m->name == mc->name) {
    //         if (m->isGeneric) {
    //             generics.push_back(m);
    //         } else {
    //             list.push_back(m);
    //         }
    //     }
    // }
    for (auto &item : unit->items) {
        if (item->isMethod()) {
            auto m = dynamic_cast<Method *>(item.get());
            if (m->name != mc->name) {
                continue;
            }
            if (m->isGeneric) {
                generics.push_back(m);
            } else {
                list.push_back(m);
            }
        }
    }
    if (curImpl) {
        //static sibling
        for (auto &m : curImpl->methods) {
            if (!m->self && m->name == mc->name) {
                if (m->isGeneric) {
                    generics.push_back(m.get());
                } else {
                    list.push_back(m.get());
                }
            }
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

RType *Resolver::handleCallResult(std::vector<Method *> &list, std::vector<Method *> &generics, MethodCall *mc) {
    //prefer generic methods
    std::vector<Method *> real;
    MethodResolver mr(this);
    real = mr.filter(list, mc);
    if (real.empty()) {
        real = mr.filter(generics, mc);
    }
    if (real.empty()) {
        if (list.empty() && generics.empty()) {
            error("no such method: " + mc->print());
        }
        std::string s;
        for (auto m : list) {
            s += mangle(m) + "\n";
        }
        for (auto m : generics) {
            s += mangle(m) + "\n";
        }
        error("method: " + mc->print() + " not found from candidates:\n " + s);
    }

    if (real.size() > 1) {
        std::string s;
        for (auto m : real) {
            s += mangle(m) + "\n";
        }
        error("method:  " + mc->print() + " has " +
              std::to_string(real.size()) + " candidates;\n" + s);
    }
    auto target = real[0];
    if (target->isGeneric) {
        std::map<std::string, Type *> typeMap;
        if (mc->typeArgs.empty()) {
            //infer
            for (auto ta : target->typeArgs) {
                typeMap[ta->name] = nullptr;
            }
            if (mc->scope) {
                auto scope = resolve(mc->scope.get());
                for (int i = 0; i < scope->type->typeArgs.size(); i++) {
                    typeMap[target->typeArgs[i]->name] = scope->type->typeArgs[i];
                }
            }
            for (int i = 0; i < mc->args.size(); i++) {
                auto arg_type = resolve(mc->args[i]);
                auto target_type = target->params[i]->type.get();
                MethodResolver::infer(arg_type->type, target_type, typeMap);
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
                auto argt = resolve(mc->typeArgs[i]);
                typeMap[target->typeArgs[i]->name] = argt->type;
            }
        }
        auto newMethod = mr.generateMethod(typeMap, target, mc);
        target = newMethod;
    }
    auto res = clone(resolveType(target->type.get()));
    res->targetMethod = target;
    if (target->unit != unit.get()) {
        usedMethods.push_back(target);
    }
    return res;
}

Method *MethodResolver::generateMethod(std::map<std::string, Type *> &map, Method *m, MethodCall *mc) {
    for (auto gm : r->generatedMethods) {
        if (isSame(mc, gm)) {
            return gm;
        }
    }
    auto gen = new Generator(map);
    auto res = (Method *) gen->visitMethod(m);
    res->parent = m->parent;
    if (m->self) {
        auto impl = dynamic_cast<Impl *>(m->parent);
        auto scope = r->resolve(mc->scope.get());
        auto newImpl = new Impl(scope->type);
        res->parent = newImpl;
        //res->self->type.reset(clone(scope->type));
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

bool MethodResolver::isSame(MethodCall *mc, Method *m) {
    if (mc->name != m->name) return false;
    if (!m->typeArgs.empty()) {
        if (!mc->typeArgs.empty()) {
            //size mismatch
            if (mc->typeArgs.size() != m->typeArgs.size()) return false;
        }
        if (!m->isGeneric) {
            //check if args are compatible with generic type params
            for (int i = 0; i < mc->typeArgs.size(); i++) {
                if (mc->typeArgs[i]->print() != m->typeArgs[i]->print()) return false;
            }
        }
    }
    if (m->parent && m->parent->isImpl() && mc->scope) {
        auto impl = dynamic_cast<Impl *>(m->parent);
        if (!impl->isGeneric && !impl->type->typeArgs.empty()) {
            auto scope = r->resolve(mc->scope.get());
            //check they belong same impl
            for (int i = 0; i < scope->type->typeArgs.size(); i++) {
                if (scope->type->typeArgs[i]->print() != impl->type->typeArgs[i]->print()) return false;
            }
        }
    }
    //check if args are compatible with non generic params
    return checkArgs(mc, m);
}