#include "parser/Ast.h"
#include "AstCopier.h"

static Type clone(const Type &type) {
    AstCopier copier;
    auto tmp = type;
    return *(Type *) std::any_cast<Expression *>(tmp.accept(&copier));
}

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