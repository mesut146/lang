#include "parser/Ast.h"

static Type clone(const Type &type) {
    if (type.isPointer()) {
        return Type(Type::Pointer, clone(*type.scope.get()));
    } else if (type.isArray()) {
        return Type(clone(*type.scope.get()), type.size);
    } else if (type.isSlice()) {
        return Type(Type::Slice, clone(*type.scope.get()));
    } else {
        Type res(type.name);
        if (type.scope) {
            res.scope = std::make_unique<Type>(clone(*type.scope.get()));
        }
        res.typeArgs.insert(res.typeArgs.end(), type.typeArgs.begin(), type.typeArgs.end());
        return res;
    }
}

/*static Type clone(Ptr<Type> &type) {
    return clone(type.get());
}*/

static Type makeSelf(const Type &scope) {
    if (scope.isPrim()) return clone(scope);
    return Type(Type::Pointer, scope);
}

bool isGeneric(const Type &type, const std::vector<Type> &typeParams);

static bool isUnsigned(const Type &type) {
    auto s = type.print();
    return s == "u8" || s == "u16" ||
           s == "u32" || s == "u64";
}

static uint64_t max_for(const Type &type) {
    auto s = type.print();
    int bits = sizeMap[s];
    if (isUnsigned(type)) {
        auto x = 1ULL << (bits - 1);
        //do this not to overflow
        return x - 1 + x;
    }
    return (1ULL << (bits - 1)) - 1;
}