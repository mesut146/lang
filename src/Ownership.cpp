#include "Ownership.h"
#include "Compiler.h"

/*Ownership::Ownership(Compiler *compiler, Method *m) : compiler(compiler), method(m) {
    this->r = compiler->resolv.get();
    this->last_scope = nullptr;
}*/

void Ownership::init(Method *m) {
    this->method = m;
    this->scope = VarScope{};
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
    for (auto &mv : last_scope->moves) {
        if (mv.rhs.id == expr->id) {
            r->err(expr, "use after move, line: " + std::to_string(mv.line));
        }
    }
}

Variable *Ownership::add(std::string &name, Type &type, llvm::Value *ptr, int id, int line) {
    auto rt = r->resolve(type);
    if (!isDropType(rt)) return nullptr;
    if (id == -1) {
        throw std::runtime_error("add id");
    }
    last_scope->vars.push_back(Variable(name, type, ptr, id, line));
    return &last_scope->vars.back();
}

Variable *Ownership::find(std::string &name, int id) {
    auto sc = last_scope;
    while (sc) {
        for (int i = 0; i < sc->vars.size(); ++i) {
            auto &v = sc->vars[i];
            if (v.name == name && v.id == id) {
                return &v;
            }
        }
        sc = sc->parent;
    }
    return nullptr;
}
Variable *Ownership::findLhs(Expression *expr) {
    auto sc = last_scope;
    while (sc != nullptr) {
        for (int i = 0; i < sc->vars.size(); ++i) {
            auto &v = sc->vars[i];
            if (v.id == expr->id) {
                return &v;
            }
        }
        sc = sc->parent;
    }
    r->err(expr, "cant find lhs");
    return nullptr;
}

void Ownership::doMove(Expression *expr) {
    if (true) return;
    auto rt = r->resolve(expr);
    if (!isDropType(rt)) return;
    auto sn = dynamic_cast<SimpleName *>(expr);
    if (sn) {
        check(expr);
        auto id = rt.vh.value().id;
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
}

Move *Ownership::isMoved(SimpleName *expr) {
    auto rt = r->resolve(expr);
    if (!isDropType(rt)) return nullptr;
    auto id = rt.vh.value().id;
    /*for (int j = scopes.size() - 1; j >= 0; --j) {
        auto &scope = scopes[j];
        for (int i = 0; i < scope.moved.size(); ++i) {
            auto &v = scope.moved[i];
            if (v.name == expr->name && v.id == id) {
                return &v;
            }
        }
    }*/
    return nullptr;
}

std::vector<VarScope *> Ownership::rev_scopes() {
    std::vector<VarScope *> res;
    auto sc = last_scope;
    while (sc != nullptr) {
        res.push_back(sc);
        sc = sc->parent;
    }
    return res;
}

std::pair<Move *, VarScope *> Ownership::is_assignable(Expression *expr) {
    auto fa = dynamic_cast<FieldAccess *>(expr);
    if (fa) {
        auto rt_new = r->resolve(fa->scope);
        if (rt_new.type.isPointer()) {
            r->err(expr, "move field of ptr");
        }
        if (isDropType(rt_new)) {
            //r->err(expr, "partial move");
        }
        for (auto scp : rev_scopes()) {
            for (auto &mv : scp->moves) {
                auto rt_old = r->resolve(mv.rhs.expr);
                if (rt_old.vh.has_value() && rt_new.vh.has_value() && rt_old.vh.value().id == rt_new.vh.value().id) {
                    if (!scp->ends_with_return) {
                        r->err(expr, "assign field to moved variable, moved in " + std::to_string(mv.line));
                    }
                    return {nullptr, nullptr};
                }
            }
        }
    }
    return {nullptr, nullptr};
}

void Ownership::doAssign(Expression *lhs, Expression *rhs) {
    is_assignable(lhs);
    auto rt = r->resolve(rhs);
    if (!isDropType(rt)) return;
    check(rhs);
    //if lhs is moved too, reassign
    last_scope->moves.push_back(Move::make_var_move(lhs, Object::make(rhs)));
}

//redeclare var
void Ownership::endAssign(Expression *lhs) {
    if (true) return;
    auto rt = r->resolve(lhs);
    if (!isDropType(rt)) return;
    auto sn = dynamic_cast<SimpleName *>(lhs);
    /*if (sn) {
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
    }*/
}


void Ownership::doMoveReturn(Expression *expr) {
    if (true) return;
    check(expr);
    last_scope->moves.push_back(Move::make_transfer(Object::make(expr)));
}

void Ownership::moveToField(Expression *expr) {
    check(expr);
    auto rt = r->resolve(expr);
    if (!isDropType(rt)) return;
    last_scope->moves.push_back(Move::make_transfer(Object::make(expr)));
    doMove(expr);
}

void Ownership::doMoveCall(Expression *arg) {
    check(arg);
    last_scope->moves.push_back(Move::make_transfer(Object::make(arg)));
}

void Ownership::doReturn() {
    endScope(last_scope);
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
    auto m = findDrop(c->unit.get(), type);
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
    throw std::runtime_error("cant find drop method for " + type.print());
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

void call_drop(Ownership *own, Type &type, llvm::Value *ptr) {
    llvm::Function *proto;
    //todo, separate from compiler protos
    if (own->protos.contains(type.print())) {
        proto = own->protos[type.print()];
    } else {
        auto drop_method = findDrop(own->compiler, type);
        proto = own->compiler->make_proto(drop_method);
        own->protos[type.print()] = proto;
    }
    std::vector<llvm::Value *> args{ptr};
    own->compiler->loc(0, 0);
    own->compiler->Builder->CreateCall(proto, args);
}

//Drop::drop(ptr) -> Type::drop(self)
void Ownership::drop(Expression *expr, llvm::Value *ptr) {
    //if (true) return;
    auto rt = r->resolve(expr);
    if (!isDrop(rt.targetDecl)) return;
    print("dropping " + expr->print());
    call_drop(this, rt.type, ptr);
}

void Ownership::drop(Variable *v) {
    call_drop(this, v->type, v->ptr);
}

bool is_moved(Ownership *own, Variable &v, VarScope &scp) {
    auto cur = &scp;
    while (cur) {
        for (auto &v : cur->vars) {
            for (auto &mv : cur->moves) {
                //todo redeclare?
                auto rt = own->r->resolve(mv.rhs.expr);
                if (rt.vh && rt.vh->id == v.id) {
                    return true;
                }
            }
        }
        cur = cur->parent;
    }
    cur = &scp;
    while (cur) {
        for (auto &v : cur->vars) {
            for (auto &mv : cur->moves) {
                //todo redeclare?
                auto rt = own->r->resolve(mv.rhs.expr);
                if (rt.vh && rt.vh->id == v.id) {
                    return true;
                }
            }
        }
        cur = cur->next_scope;
    }
    return false;
}

//drop vars in this scope
void Ownership::endScope(VarScope *s) {
    //if (true) return;
    print("endscope " + printMethod(method));
    for (auto &obj : s->objects) {
        //todo is valid
        bool is_moved = false;
        for (auto &mv : s->moves) {
            if (mv.rhs.id == obj.id) {
                is_moved = true;
                break;
            }
        }
        if (!is_moved) {
            drop(obj.expr, obj.ptr);
        }
    }
    for (auto &v : s->vars) {
        if (!is_moved(this, v, *s)) {
            std::cout << "drop var " << v.name << ": " << v.type.print() << " id: " << v.id << " line: " << v.line << "\n";
            drop(&v);
        }
    }
}