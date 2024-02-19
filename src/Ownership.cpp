#include "Ownership.h"
#include "Compiler.h"

Ownership::Ownership(Compiler *compiler, Method *m) : compiler(compiler), method(m) {
    this->r = compiler->resolv.get();
    this->last_scope = &scope;
}

bool Ownership::isDrop(BaseDecl *decl) {
    if (decl == nullptr) return false;
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

void Ownership::check(Expression *expr) {
    auto sn = dynamic_cast<SimpleName *>(expr);
    if (sn) {
        auto moved = isMoved(sn);
        if (moved != nullptr) {
            r->err(expr, "use after move, line: " + std::to_string(moved->moveLine));
        }
    }
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
        check(expr);
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
        return;
    }
    for (int i = 0; i < objects.size(); ++i) {
        auto &ob = objects[i];
        if (ob.expr->id == expr->id) {
            objects.erase(objects.begin() + i);
            break;
        }
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

void Ownership::moveToField(Expression *expr) {
    doMove(expr);
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

void Ownership::doReturn() {
    if (!objects.empty()) {
        std::cout << "return " << printMethod(method) << "\n";
    }
    for (auto &ob : objects) {
        std::cout << "drop " << ob.expr->print() << "\n";
    }
}

Method *findDrop(Unit *unit, const Type &type) {
    for (auto &it : unit->items) {
        auto impl = dynamic_cast<Impl *>(it.get());
        if (!impl) continue;
        if (impl->trait_name.has_value() && impl->trait_name->print() == "Drop" && impl->type.print() == type.print()) {
            return &impl->methods.at(0);
        }
    }
    return nullptr;
}

Method *findDrop(Compiler *c, const Type &type) {
    auto m = findDrop(c, type);
    if (m) {
        return m;
    }
    for (auto &is : c->resolv->get_imports()) {
        auto r2 = c->resolv->getResolver(is, c->resolv->root);
        auto m2 = findDrop(r2->unit.get(), type);
        if (m2) {
            return m2;
        }
    }
    throw std::runtime_error("cant find drop method");
}

Method *findDrop0(Compiler *c, Expression *expr) {
    //{expr}.drop()
    MethodCall mc;
    mc.id = ++Node::last_id;
    mc.scope.reset(expr);
    mc.name = "drop";
    auto res = c->resolv->resolve(&mc);
    mc.scope.release();
    if (res.targetMethod == nullptr) {
        throw std::runtime_error("can't find drop");
    }
    return res.targetMethod;
}

//Drop::drop(ptr) -> Type::drop(self)
void Ownership::drop(Expression *expr, llvm::Value *ptr) {
    auto rt = r->resolve(expr);
    if (!isDrop(rt.targetDecl)) return;
    print("dropping " + expr->print() + "\n");
    auto drop_method = findDrop0(compiler, expr);
    auto proto = compiler->make_proto(drop_method);
    std::vector<llvm::Value *> args{ptr};
    compiler->Builder->CreateCall(proto, args);
}
