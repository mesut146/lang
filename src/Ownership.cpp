#include "Ownership.h"
#include "Compiler.h"

int VarScope::last_id = 0;

template<class T>
std::vector<T *> rev(std::vector<T> &vec) {
    std::vector<T *> res;
    for (int i = vec.size() - 1; i >= 0; --i) {
        res.push_back(&vec[i]);
    }
    return res;
}

/*Ownership::Ownership(Compiler *compiler, Method *m) : compiler(compiler), method(m) {
    this->r = compiler->resolv.get();
    this->last_scope = nullptr;
}*/

void Ownership::init(Method *m) {
    this->method = m;
    auto ms = VarScope(ScopeId::MAIN, ++VarScope::last_id);
    scope_map.insert({ms.id, ms});
    this->main_scope = &scope_map.at(ms.id);
    this->last_scope = main_scope;
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

bool Ownership::isDropType(Expression *e) {
    auto rt = r->resolve(e);
    return isDropType(rt);
}

Variable *getVar(Ownership *own, Expression *expr) {
    auto rt = own->r->resolve(expr);
    if (!own->isDropType(rt)) return nullptr;
    auto id = rt.vh.value().id;
    for (auto scp : own->rev_scopes()) {
        for (auto &v : scp->vars) {
            if (v.id == id) {
                return &v;
            }
        }
    }
    return nullptr;
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
void Ownership::doMove(Expression *expr) {
    if (true) return;
    auto rt = r->resolve(expr);
    if (!isDropType(rt)) return;
    auto sn = dynamic_cast<SimpleName *>(expr);
    if (sn) {
        check(expr);
        //auto id = rt.vh.value().id;
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
        if (sc->parent == -1) break;
        sc = &getScope(sc->parent);
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

void Ownership::endAssign(Expression *lhs, Expression *rhs) {
    is_assignable(lhs);
    auto rt = r->resolve(rhs);
    if (!isDropType(rt)) return;
    check(rhs);
    auto v = getVar(this, lhs);
    if (v) {
        last_scope->moves.push_back(Move::make_var_move(v, Object::make(rhs)));
    } else {
        last_scope->moves.push_back(Move::make_var_move(lhs, Object::make(rhs)));
    }
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
    //todo transfer or ?
    doMove(expr);
    last_scope->moves.push_back(Move::make_transfer(Object::make(expr)));
}

void Ownership::doMoveCall(Expression *arg) {
    check(arg);
    if (isDropType(arg)) {
        last_scope->moves.push_back(Move::make_transfer(Object::make(arg)));
    }
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
    llvm::Function *proto = nullptr;
    //todo, separate from compiler protos
    if (own->protos.contains(type.print())) {
        proto = own->protos[type.print()];
    } else {
        auto drop_method = findDrop(own->compiler, type);
        auto mangled = mangle(drop_method);
        if (own->compiler->funcMap.contains(mangled)) {
            proto = own->compiler->funcMap[mangled];
        } else {
            proto = own->compiler->make_proto(drop_method);
        }
        own->protos[type.print()] = proto;
    }
    std::vector<llvm::Value *> args{ptr};
    own->compiler->loc(0, 0);
    own->compiler->Builder->CreateCall(proto, args);
}

bool is_moved_from(Move &mv, Variable &v, Resolver *r) {
    auto rt = r->resolve(mv.rhs.expr);
    if (rt.vh && rt.vh->id == v.id) {
        return true;
    }
    return false;
}
bool is_moved_to(Move &mv, Variable &v, Resolver *r) {
    if (mv.lhs) {
        return mv.lhs->id == v.id;
    }
    if (mv.lhs_expr) {
        auto rt = r->resolve(mv.lhs_expr);
        if (rt.vh && rt.vh->id == v.id) {
            return true;
        }
    }
    return false;
}

bool is_moved(Ownership *own, Variable &v, VarScope &scp) {
    for (auto &mv : scp.moves) {
        if (is_moved_from(mv, v, own->r)) {
            return true;
        }
    }
    for (auto cur_id : scp.scopes) {
        auto &cur = own->getScope(cur_id);
        for (auto &mv : cur.moves) {
            //todo redeclare?
            if (is_moved_from(mv, v, own->r)) {
                return true;
            }
        }
    }
    return false;
}

Move *get_move(Ownership *own, Variable &v, VarScope &scp) {
    for (auto mv : rev(scp.moves)) {
        if (is_moved_from(*mv, v, own->r)) {
            return mv;
        }
        if (is_moved_to(*mv, v, own->r)) {
            return mv;
        }
    }
    for (auto cur_id : scp.scopes) {
        auto &cur = own->getScope(cur_id);
        for (auto mv : rev(cur.moves)) {
            //todo redeclare?
            if (is_moved_from(*mv, v, own->r)) {
                return mv;
            }
            if (is_moved_to(*mv, v, own->r)) {
                return mv;
            }
        }
    }
    return nullptr;
}

void Ownership::drop(Variable *v) {
    call_drop(this, v->type, v->ptr);
}

void Ownership::drop(Expression *expr, llvm::Value *ptr) {
    //if (true) return;
    auto rt = r->resolve(expr);
    if (!isDrop(rt.targetDecl)) return;
    auto v = getVar(this, expr);
    if (v) {
        std::cout << "v id: " << v->id << " line: " << v->line << "\n";
        if (v->id == 2313) {
            int aa = 55;
        }
        auto last_mv = get_move(this, *v, *last_scope);
        if (!last_mv) {//nothing, just drop
            std::cout << "drop var " << v->name << ": " << v->type.print() << " id: " << v->id << " line: " << v->line << "\n";
            drop(v);
        } else if (is_moved_to(*last_mv, *v, r)) {//moved and reassign, drop
            std::cout << "drop var " << v->name << ": " << v->type.print() << " id: " << v->id << " line: " << v->line << "\n";
            drop(v);
        } else {
            //moved from, reassign, no drop
        }
        // if (!is_moved(this, *v, *last_scope)) {
        //     std::cout << "dropping " << expr->print() << " line: " << expr->line << "\n";
        //     call_drop(this, rt.type, ptr);
        // }
    } else {
        throw std::runtime_error("novar drop other " + expr->print());
    }
}

bool isDropped(Variable &v, VarScope &scope, Ownership *own) {
    for (auto mv : rev(scope.moves)) {
        if (mv->lhs == nullptr && mv->lhs_expr == nullptr) {//transfer
            return true;
        }
        if (is_moved_to(*mv, v, own->r)) {//init causes this to drop
            return false;
        }
    }
    for (auto scp_id : scope.scopes) {
        auto ch_scope = own->getScope(scp_id);
        if (isDropped(v, ch_scope, own)) {
            return true;
        }
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
    if (method->name == "if1") {
        int aa = 5555;
    }
    for (auto &v : s->vars) {
        if (!isDropped(v, *s, this)) {
            drop(&v);
        }
        /*auto last_mv = get_move(this, v, *s);
        if (!last_mv) {//nothing, just drop
            std::cout << "drop var " << v.name << ": " << v.type.print() << " id: " << v.id << " line: " << v.line << "\n";
            drop(&v);
        } else if (is_moved_to(*last_mv, v, r)) {//reassign, drop
            std::cout << "drop var " << v.name << ": " << v.type.print() << " id: " << v.id << " line: " << v.line << "\n";
            drop(&v);
        }*/
    }

    if (s->type == ScopeId::ELSE) {
        auto &if_scope = getScope(s->sibling);
        //if then_scope drops var, else_scope must drop it too
        for (auto &mv : if_scope.moves) {
            auto rt = r->resolve(mv.rhs.expr);
            if (rt.vh.has_value()) {
                auto v = getVar(this, mv.rhs.expr);
                if (isDropped(*v, if_scope, this)) {
                    //transferred, so drop
                    drop(v);
                }
            }
        }
    }
}