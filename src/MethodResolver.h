#pragma once

#include "Resolver.h"

class MethodResolver {
    Resolver *r;

public:
    MethodResolver(Resolver *r) : r(r) {}

    //get cached or generate method
    Method *generateMethod(std::map<std::string, Type *> &map, Method *m, MethodCall *mc);

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
                    //todo move this
                    r->resolve(type);
                }
                for (auto &m : impl->methods) {
                    if (m->name == name) list.push_back(m.get());
                }
            }
        }
    }

    static bool isGeneric(Type *type, std::vector<Type *> &typeParams) {
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

    static bool isCompatible(Type *arg, Type *target) {
        std::vector<Type *> typeParams;
        return isCompatible(arg, target, typeParams);
    }

    static bool isCompatible(Type *arg, Type *target, std::vector<Type *> &typeParams);

    bool checkArgs(MethodCall *mc, Method *m);

    bool checkArgs(std::vector<Expression *> &args, std::vector<Param *> &params, Method *m);

    bool isSame(MethodCall *mc, Method *m);
    static void infer(Type *arg, Type *prm, std::map<std::string, Type *> &typeMap);
};