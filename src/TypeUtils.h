#pragma once

#include "AstCopier.h"
#include "parser/Ast.h"

static Type clone(const Type &type) {
    AstCopier copier;
    auto tmp = type;
    return *(Type *) std::any_cast<Expression *>(tmp.accept(&copier));
}

static Type makeSelf(const Type &scope) {
    //if (scope.isPrim()) return clone(scope);
    return Type(Type::Pointer, scope);
}

static bool hasGeneric(const Type &type, const std::vector<Type> &typeParams) {
    if (type.isSlice() || type.isArray() || type.isPointer()) {
        auto elem = type.scope.get();
        return hasGeneric(*elem, typeParams);
    }
    if (type.scope) throw std::runtime_error("hasGeneric::scope");
    if (type.typeArgs.empty()) {
        for (auto &tp : typeParams) {
            if (tp.print() == type.print()) return true;
        }
    } else {
        for (auto &ta : type.typeArgs) {
            if (hasGeneric(ta, typeParams)) return true;
        }
    }
    return false;
}

static bool isGeneric2(const std::string &type, const std::vector<Type> &typeParams) {
    for (auto &tp : typeParams) {
        if (tp.print() == type) return true;
    }
    return false;
}

static bool isGeneric(const Type &type, const std::vector<Type> &typeParams) {
    if (type.isPointer()) return isGeneric(*type.scope.get(), typeParams);
    if (type.isSlice() || type.isArray() || type.isPointer()) return false;
    if (type.scope) throw std::runtime_error("isGeneric::scope");
    if (type.typeArgs.empty()) {
        for (auto &tp : typeParams) {
            if (tp.print() == type.print()) return true;
        }
    } else {
        for (auto &ta : type.typeArgs) {
            if (isGeneric(ta, typeParams)) return true;
        }
    }
    return false;
}

static bool isUnsigned(const Type &type) {
    auto s = type.print();
    return s == "u8" || s == "u16" ||
           s == "u32" || s == "u64";
}
static bool isSigned(const Type &type) {
    auto s = type.print();
    return s == "i8" || s == "i16" ||
           s == "i32" || s == "i64";
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

static Type getType(int bits) {
    if (bits == 32) return Type("i32");
    if (bits == 64) return Type("i64");
    throw std::runtime_error("getType");
}

static std::map<std::string, Type> get_map_from(BaseDecl *bd) {
    std::map<std::string, Type> map;
    return map;
}

static void init_self_type(Method &m, const Type &type) {
    if (m.self && !m.self->type.has_value()) {
        if (m.self->is_deref) {
            m.self->type = clone(type);
        } else {
            m.self->type = type.toPtr();
        }
    }
}

static void init_self_type(Impl *imp) {
    for (auto &m : imp->methods) {
        init_self_type(m, imp->type);
    }
}

enum class ExitType {
    NONE,
    RETURN,
    PANIC,
    BREAK,
    CONTINE,
};

struct Exit {
    ExitType kind;
    std::unique_ptr<Exit> if_kind;
    std::unique_ptr<Exit> else_kind;

    Exit(const ExitType &kind) : kind(kind) {}
    Exit(const Exit &obj) {
        operator=(obj);
    }
    Exit() {}

    void operator=(const Exit &rhs) {
        kind = rhs.kind;
        if (rhs.if_kind) {
            if_kind = std::make_unique<Exit>(*rhs.if_kind);
        }
        if (rhs.else_kind) {
            else_kind = std::make_unique<Exit>(*rhs.else_kind);
        }
    }

    bool is_return();

    bool is_jump();

    bool is_panic();
    
    bool is_exit();

    static Exit get_exit_type(Statement *stmt);
};