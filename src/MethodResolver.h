#pragma once

#include "Resolver.h"

class MethodResolver {
    Resolver *r;

public:
    MethodResolver(Resolver *r) : r(r) {}


    //get cached or generate method
    Method *generateMethod(std::unordered_map<std::string, Type *> &map, Method *m, MethodCall *mc) {
        for (auto gm : r->generatedMethods) {
            if (isSame(mc, gm)) {
                print("reuse: " + mc->name);
                return gm;
            }
        }
        auto gen = new Generator(map);
        auto res = (Method *) gen->visitMethod(m);
        print("generateMethod: " + res->print());
        r->generatedMethods.push_back(res);
        return res;
    }

    std::vector<Method *> filter(std::vector<Method *> &list, MethodCall *mc) {
        std::vector<Method *> res;
        for (auto m : list) {
            if (isSame(mc, m)) {
                res.push_back(m);
            }
        }
        return res;
    }

    void getMethods(Type *type, std::string &name, std::vector<Method *> &list) {
        for (auto &i : r->unit->items) {
            if (i->isImpl()) {
                auto impl = dynamic_cast<Impl *>(i.get());
                if (impl->type->name != type->name) continue;
                if (!impl->type->typeArgs.empty()) {
                    r->resolve(type);
                }
                for (auto &m : impl->methods) {
                    if (m->name == name) list.push_back(m.get());
                }
            }
        }
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

    bool isCompatible(Type *arg, Type *target, std::vector<Type *> &typeParams) {
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

    bool checkArgs(MethodCall *mc, Method *m) {
        for (int i = 0; i < mc->args.size(); i++) {
            auto t1 = r->resolve(mc->args[i])->type;
            auto t2 = m->params[i]->type.get();
            if (m->isGeneric) {
                if (!isCompatible(t1, t2, m->typeArgs)) {
                    return false;
                }
            } else {
                //concrete method pass dummy type params
                std::vector<Type *> typeParams;
                if (!isCompatible(t1, t2, typeParams)) {
                    return false;
                }
            }
        }
        return true;
    }

    bool isSame(MethodCall *mc, Method *m) {
        if (mc->name != m->name) return false;
        if (mc->args.size() != m->params.size()) return false;
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
        //check if args are compatible with non generic params
        return checkArgs(mc, m);
    }
};