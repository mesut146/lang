#include "parser/Ast.h"

static Type *clone(Type *type) {
    if (type->isPointer()) {
        auto ptr = dynamic_cast<PointerType *>(type);
        return new PointerType(clone(ptr->type));
    } else if (type->isArray()) {
        auto arr = dynamic_cast<ArrayType *>(type);
        return new ArrayType(clone(arr->type), arr->size);
    } else if (type->isSlice()) {
        auto slice = dynamic_cast<SliceType *>(type);
        return new SliceType(clone(slice->type));
    } else {
        auto res = new Type(type->name);
        if (type->scope) {
            res->scope.reset(clone(type->scope.get()));
        }
        res->typeArgs.insert(res->typeArgs.end(), type->typeArgs.begin(), type->typeArgs.end());
        return res;
    }
}