#pragma once

#include "Resolver.h"


struct Signature {
    MethodCall *mc = nullptr;
    Method *m = nullptr;
    std::vector<Type> args;
    std::optional<RType> scope;
    Type ret;
    Resolver *r = nullptr;

    static Signature make(MethodCall *mc, Resolver *r);
    static Signature make(Method *m, const std::map<std::string, Type> &map);
    std::string print();
};

/*struct Result {
    std::string msg;
    bool exact;
};*/

using SigResult = std::variant<std::string, bool>;

//using std::vector<std::string> Names;

class MethodResolver {
    Resolver *r;

public:
    MethodResolver(Resolver *r) : r(r) {}

    //get cached or generate method
    Method *generateMethod(std::map<std::string, Type> &map, Method *m, Signature &sig);
    void findMethod(std::string &name, std::vector<Signature> &list);
    void getMethods(Signature &sig, std::vector<Signature> &list, bool imports);

    static std::optional<std::string> isCompatible(const RType &arg, const Type &target) {
        std::vector<Type> typeParams;
        return isCompatible(arg, target, typeParams);
    }

    static std::optional<std::string> isCompatible(const RType &arg, const Type &target, const std::vector<Type> &typeParams);

    static void infer(const Type &arg, const Type &prm, std::map<std::string, std::optional<Type>> &typeMap);

    SigResult checkArgs(Signature &sig, Signature &sig2);

    SigResult isSame(Signature &sig, Signature &sig2);

    std::vector<Signature> collect(Signature &sig);

    RType handleCallResult(Signature &sig);
};
