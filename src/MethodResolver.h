#pragma once

#include "Resolver.h"


struct Signature {
    MethodCall *mc = nullptr;
    Method *m = nullptr;
    std::vector<Type> args;
    std::optional<RType> scope;
    std::optional<RType> real_scope;//mc original scope, no deref
    Type ret;
    Resolver *r = nullptr;

    static Signature make(MethodCall *mc, Resolver *r);
    static Signature make(Method *m, const std::map<std::string, Type> &map);
    std::string print();

    Type *get_self() { return &m->self->type.value(); }
};

/*struct Result {
    std::string msg;
    bool exact;
};*/

using SigResult = std::variant<std::string, bool>;

struct CompareResult {
    std::string err;
    bool has_err = false;
    bool cast = false;

    CompareResult() = default;
    CompareResult(const std::string &err) : err(err), has_err(true) {}
    CompareResult(const std::string &&err) : err(err), has_err(true) {}

    bool is_err() { return has_err; }

    static CompareResult make_casted() {
        CompareResult res;
        res.cast = true;
        return res;
    }
};

class MethodResolver {
    Resolver *r;

public:
    MethodResolver(Resolver *r) : r(r) {}

    //get cached or generate method
    Method *generateMethod(std::map<std::string, Type> &map, Method *m, Signature &sig);
    void findMethod(std::string &name, std::vector<Signature> &list);
    void getMethods(Signature &sig, std::vector<Signature> &list, bool imports);

    static CompareResult isCompatible(const RType &arg, const Type &target) {
        std::vector<Type> typeParams;
        return isCompatible(arg, target, typeParams);
    }

    static CompareResult isCompatible(const RType &arg, const Type &target, const std::vector<Type> &typeParams);

    static void infer(const Type &arg, const Type &prm, std::map<std::string, std::optional<Type>> &typeMap);

    SigResult checkArgs(Signature &sig, Signature &sig2);

    SigResult isSame(Signature &sig, Signature &sig2);

    std::vector<Signature> collect(Signature &sig);

    RType handleCallResult(Signature &sig);
};
