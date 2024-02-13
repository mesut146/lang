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
                    scope.moved.push_back(v2);
                    scope.vars.erase(scope.vars.begin() + i);
                    break;
                }
            }
        }
        return;
    }
    auto fa = dynamic_cast<FieldAccess *>(expr);
    if (fa) {
        throw std::runtime_error("domove " + expr->print());
    }
}

Variable *Ownership::isMoved(SimpleName *expr) {
    auto rt = r->resolve(expr);
    if (!isStruct(rt.type)) return nullptr;
    if (rt.type.isString()) return nullptr;
    auto id = rt.vh.value().id;
    for (auto &v : moved) {
        if (v.name == expr->name && v.id == id) return &v;
    }
    return nullptr;
}