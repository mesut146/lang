#include "Ownership.h"
#include "Resolver.h"

bool isDrop(BaseDecl *decl, Resolver *r) {
    if (decl->isDrop()) return true;
    auto sd = dynamic_cast<StructDecl *>(decl);
    if (sd) {
        for (auto &fd : sd->fields) {
            if (!isStruct(fd.type)) continue;
            auto rt = r->resolve(fd.type);
            if (isDrop(rt.targetDecl, r)) return true;
        }
    } else {
        auto ed = dynamic_cast<EnumDecl *>(decl);
        //iter variants
        for (auto &v : ed->variants) {
            //iter fields
            for (auto &fd : v.fields) {
                if (!isStruct(fd.type)) continue;
                auto rt = r->resolve(fd.type);
                if (isDrop(rt.targetDecl, r)) return true;
            }
        }
    }
    return false;
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
    if (!isStruct(rt.type)) return;
    if (rt.type.isString()) return;
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
        doMove(fa->scope);
        //r->err(expr, "domove");
    }
}

Variable *Ownership::isMoved(SimpleName *expr) {
    auto rt = r->resolve(expr);
    if (!isStruct(rt.type)) return nullptr;
    if (rt.type.isString()) return nullptr;
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
    if (!isStruct(rt.type)) return;
    if (rt.type.isString()) return;
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