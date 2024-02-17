#include "Ownership.h"
#include "Resolver.h"

bool Ownership::isDrop(BaseDecl *decl) {
    if (decl->isDrop()) return true;
    auto sd = dynamic_cast<StructDecl *>(decl);
    if (sd) {
        for (auto &fd : sd->fields) {
            if (isDropType(fd.type)) return true;
        }
    } else {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        //iter variants
        for (auto &v : ed->variants) {
            //iter fields
            for (auto &fd : v.fields) {
                if (isDropType(fd.type)) return true;
            }
        }
    }
    return false;
}

bool Ownership::isDropType(const Type &type) {
    if (type.isString() || type.isSlice()) return false;
    if (!isStruct(type)) return false;
    if (type.isArray()) {
        auto elem = type.scope.get();
        return isDropType(*elem);
    }
    auto rt = r->resolve(type);
    return isDrop(rt.targetDecl);
}

bool Ownership::isDropType(const RType &rt) {
    auto &type = rt.type;
    if (type.isString() || type.isSlice()) return false;
    if (!isStruct(type)) return false;
    if (type.isArray()) {
        auto elem = type.scope.get();
        return isDropType(*elem);
    }
    return isDrop(rt.targetDecl);
}

void Ownership::add(std::string &name, Type &type, llvm::Value *ptr, int id, int line) {
    auto rt = r->resolve(type);
    if (!isDropType(rt)) return;
    if (id == -1) {
        throw std::runtime_error("add id");
    }
    scopes.back().vars.push_back(Variable(name, ptr, id, line));
}

Variable *Ownership::find(std::string &name, int id) {
    for (int j = scopes.size() - 1; j >= 0; --j) {
        auto &scope = scopes[j];
        for (int i = 0; i < scope.vars.size(); ++i) {
            auto &v = scope.vars[i];
            if (v.name == name && v.id == id) {
                return &v;
            }
        }
    }
    return nullptr;
}

void Ownership::doMove(Expression *expr) {
    auto rt = r->resolve(expr);
    if (!isDropType(rt)) return;
    auto sn = dynamic_cast<SimpleName *>(expr);
    if (sn) {
        auto id = rt.vh.value().id;
        for (int j = scopes.size() - 1; j >= 0; --j) {
            auto &scope = scopes[j];
            for (int i = 0; i < scope.vars.size(); ++i) {
                auto &v = scope.vars[i];
                if (v.name == sn->name && v.id == id) {
                    auto v2 = v;
                    v2.moveLine = expr->line;
                    auto &last = scopes.back();
                    last.moved.push_back(v2);
                    //scope.vars.erase(scope.vars.begin() + i);
                    return;
                }
            }
        }
        return;
    }
    auto fa = dynamic_cast<FieldAccess *>(expr);
    if (fa) {
        auto scp = r->resolve(fa->scope);
        if (scp.type.isPointer()) {
            r->err(expr, "move field of ptr");
        }
        if (isDropType(scp)) {
            r->err(expr, "partial move");
        }
        doMove(fa->scope);
        //r->err(expr, "domove");
    }
}

Variable *Ownership::isMoved(SimpleName *expr) {
    auto rt = r->resolve(expr);
    if (!isDropType(rt)) return nullptr;
    auto id = rt.vh.value().id;
    for (int j = scopes.size() - 1; j >= 0; --j) {
        auto &scope = scopes[j];
        for (int i = 0; i < scope.moved.size(); ++i) {
            auto &v = scope.moved[i];
            if (v.name == expr->name && v.id == id) {
                return &v;
            }
        }
    }
    return nullptr;
}

void Ownership::doAssign(Expression *lhs, Expression *rhs) {
    doMove(rhs);
    //if lhs is moved too, reassign
}

//redeclare var
void Ownership::endAssign(Expression *lhs) {
    auto rt = r->resolve(lhs);
    if (!isDropType(rt)) return;
    auto sn = dynamic_cast<SimpleName *>(lhs);
    if (sn) {
        auto id = rt.vh.value().id;
        for (int j = scopes.size() - 1; j >= 0; --j) {
            auto &scope = scopes[j];
            for (int i = 0; i < scope.moved.size(); ++i) {
                auto &v = scope.moved[i];
                if (v.name == sn->name && v.id == id) {
                    scope.moved.erase(scope.moved.begin() + i);
                    return;
                }
            }
        }
        return;
    }
}


void Ownership::doMoveReturn(Expression *expr) {
    for (auto i = objects.begin(); i != objects.end(); ++i) {
        auto &obj = *i;
        if (obj.expr->id == expr->id) {
            //move of rvalue, release ownership
            objects.erase(i);
            break;
        }
    }
}

void Ownership::doMoveCall(Expression *arg) {
    for (auto i = objects.begin(); i != objects.end(); ++i) {
        auto &obj = *i;
        if (obj.expr->id == arg->id) {
            //move of rvalue, release ownership
            objects.erase(i);
            break;
        }
    }
    doMove(arg);
}