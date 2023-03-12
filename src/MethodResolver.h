#pragma once

#include "Resolver.h"


struct Signature {
    MethodCall *mc = nullptr;
    Method *m = nullptr;
    std::vector<Type *> args;
    std::optional<RType> scope;

    static Signature make(MethodCall *mc, Resolver *r);
    static Signature make(Method *m, Resolver *r);
};

class MethodResolver {
    Resolver *r;

public:
    MethodResolver(Resolver *r) : r(r) {}

    //get cached or generate method
    Method *generateMethod(std::map<std::string, Type *> &map, Method *m, Signature &sig);
    void findMethod(std::string &name, std::vector<Signature> &list);
    void getMethods(RType &rtype, std::string &name, std::vector<Signature> &list, bool imports);

    static bool isCompatible(Type *arg, Type *target) {
        std::vector<Type *> typeParams;
        return isCompatible(arg, target, typeParams);
    }

    static bool isCompatible(Type *arg, Type *target, std::vector<Type *> &typeParams);
    static void infer(Type *arg, Type *prm, std::map<std::string, Type *> &typeMap);

    std::optional<std::string> checkArgs(Signature &sig, Signature &sig2);

    std::optional<std::string> isSame(Signature &sig, Signature &sig2);

    std::vector<Signature> collect(Signature &sig);
    RType handleCallResult(Signature &sig);
};
