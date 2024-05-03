#include "Ownership.h"
#include "Compiler.h"
#include "MethodResolver.h"

int VarScope::last_id = 0;

bool verbose = false;
bool enabled = false;

std::string print_type(const ScopeId &type) {
    if (type == ScopeId::MAIN) {
        return "ScopeId::MAIN";
    }
    if (type == ScopeId::IF) {
        return "ScopeId::IF";
    }
    if (type == ScopeId::ELSE) {
        return "ScopeId::ELSE";
    }
    if (type == ScopeId::WHILE) {
        return "ScopeId::WHILE";
    }
    if (type == ScopeId::FOR) {
        return "ScopeId::FOR";
    }
    throw std::runtime_error("type");
}

std::string VarScope::print_info() {
    return print_type(type) + " line: " + std::to_string(line);
}

template<class T>
std::vector<T *> rev(std::vector<T> &vec) {
    std::vector<T *> res;
    for (int i = vec.size() - 1; i >= 0; --i) {
        res.push_back(&vec[i]);
    }
    return res;
}

std::vector<VarScope *> Ownership::rev_scopes() {
    std::vector<VarScope *> res;
    auto sc = last_scope;
    while (sc != nullptr) {
        res.push_back(sc);
        //todo
        // for (auto ch : sc->scopes) {
        // }
        if (sc->parent == -1) break;
        sc = &getScope(sc->parent);
    }
    return res;
}

std::string Variable::print() {
    std::stringstream s;
    s << "var{" << name << ": " << type.print() << " id: " << id << " line: " << line << "}";
    return s.str();
}

bool isMoved(Variable &v, VarScope &scope, Ownership *own, bool use_return);
void is_movable(Expression *expr, Ownership *own);
//State get_state(Variable &v, VarScope &scope, Ownership *own, bool use_return, std::set<int> &done, bool look_parent);
State get_state(const Lhs &lhs, VarScope &scope, Ownership *own, bool use_return, std::set<int> &done, bool look_parent);

State get_state(const Lhs &lhs, VarScope &scope, Ownership *own, bool use_return) {
    std::set<int> done;
    return get_state(lhs, scope, own, use_return, done, true);
}

void Ownership::init(Compiler *c) {
    this->compiler = c;
    this->r = compiler->resolv.get();
    this->protos.compiler = c;
    this->protos.protos.clear();
    scope_map.clear();
    var_map.clear();
}

void Ownership::init(Method *m) {
    //clear prev method
    scope_map.clear();
    var_map.clear();

    this->method = m;
    int id = ++VarScope::last_id;
    auto ms = VarScope(ScopeId::MAIN, id);
    ms.line = m->line;
    scope_map.insert({id, ms});
    this->main_scope = &scope_map.at(id);
    this->last_scope = main_scope;
}

bool is_drop_method(Method &m) {
    return m.name == "drop" &&
           m.parent.is_impl() &&
           m.parent.trait_type.has_value() &&
           m.parent.trait_type->print() == "Drop";
}

Method *is_drop_impl(Impl *impl, const Type &type) {
    if (!impl->trait_name.has_value() || impl->trait_name->print() != "Drop") { return nullptr; }
    auto m = &impl->methods.at(0);
    if (impl->type.print() == type.print()) {
        return m;
    }
    return nullptr;
}

Method *findDrop(Unit *unit, const Type &type, Compiler *c) {
    for (auto &[k, m] : c->resolv->drop_methods) {
        if (k == type.print()) return m;
    }
    for (auto &imp : c->resolv->generated_impl) {
        auto m = is_drop_impl(imp.get(), type);
        if (m) {
            return m;
        }
    }
    for (auto &it : unit->items) {
        auto impl = dynamic_cast<Impl *>(it.get());
        if (!impl) continue;
        if (!impl->trait_name.has_value() || impl->trait_name->print() != "Drop") continue;
        if (impl->type.name != type.name) continue;
        auto m = &impl->methods.at(0);
        if (type.typeArgs.empty()) {
            return m;
        }
        if (impl->type.print() == type.print()) {
            return m;
        }
    }
    return nullptr;
}
Method *findDrop(Compiler *c, const Type &type) {
    auto m = findDrop(c->unit.get(), type, c);
    if (m) {
        return m;
    }
    for (auto &is : c->resolv->get_imports()) {
        auto r2 = c->resolv->getResolver(is, c->resolv->root);
        auto m2 = findDrop(r2->unit.get(), type, c);
        if (m2) {
            return m2;
        }
    }
    auto rt = c->resolv->resolve(type);
    if (!rt.targetDecl) {
        throw std::runtime_error("non decl drop" + type.print());
    }
    throw std::runtime_error("findDrop " + type.print());
}

bool DropHelper::isDrop(BaseDecl *decl) {
    if (decl == nullptr) return false;
    if (decl->isDrop()) return true;
    if (decl->isClass()) {
        auto sd = dynamic_cast<StructDecl *>(decl);
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

bool DropHelper::isDropType(const Type &type) {
    if (type.isString() || type.isSlice()) return false;
    if (!isStruct(type)) return false;
    if (type.isArray()) {
        auto elem = type.scope.get();
        return isDropType(*elem);
    }
    auto rt = r->resolve(type);
    return isDrop(rt.targetDecl);
}

bool DropHelper::isDropType(const RType &rt) {
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
    DropHelper helper(r);
    auto rt = r->resolve(e);
    return helper.isDropType(rt);
}

void DropProtos::call_drop_force(Type &type, llvm::Value *ptr) {
    llvm::Function *proto = nullptr;
    //todo, separate from compiler protos
    if (protos.contains(type.print())) {
        proto = protos[type.print()];
    } else {
        auto drop_method = findDrop(compiler, type);
        auto mangled = mangle(drop_method);
        if (compiler->funcMap.contains(mangled)) {
            proto = compiler->funcMap[mangled];
        } else {
            proto = compiler->make_proto(drop_method);
        }
        protos[type.print()] = proto;
    }
    std::vector<llvm::Value *> args{ptr};
    compiler->loc(0, 0);
    compiler->Builder->CreateCall(proto, args);
}

void Ownership::addPtr(Expression *expr, llvm::Value *ptr) {
    if (!last_scope) {
        throw std::runtime_error("Ownership::addPtr");
    }
    if (isDropType(expr)) {
        last_scope->objects.push_back(Object::make(expr, ptr));
    }
}

Variable *Ownership::add(std::string &name, Type &type, llvm::Value *ptr, int id, int line) {
    if (!DropHelper::isDropType(type, r)) return nullptr;
    if (id == -1) {
        throw std::runtime_error("Ownership::add id " + name + " line: " + std::to_string(line));
    }
    var_map.insert({id, Variable(name, type, ptr, id, line, last_scope->id)});
    last_scope->vars.push_back(id);
    return &var_map.at(id);
}

void Ownership::check(Expression *expr) {
    for (auto &act : last_scope->actions) {
        if (!act.is_move()) {
            continue;
        }
        if (act.mv.rhs.id == expr->id) {
            r->err(expr, "use after move, line: " + std::to_string(act.mv.line));
        }
    }
    //is_movable(expr, this);
    auto state = get_state(Lhs(expr), *last_scope, this, false);
    if (state.is_moved()) {
        r->err(expr, "use after move, line: " + std::to_string(state.mv->line));
    }
}

// void is_movable(Expression *expr, Ownership *own) {
//     auto rt = own->r->resolve(expr);
//     if (!own->isDropType(rt)) return;
//     auto de = dynamic_cast<DerefExpr *>(expr);
//     if (de) {
//         own->r->err(expr, "can't move by deref");
//     }
//     if (rt.vh) {
//         if (rt.type.isPointer()) {
//             return;
//         }
//         auto &v = own->getVar(rt.vh->id);
//         std::set<int> done;
//         auto state = get_state(v, *own->last_scope, own, true, done);
//         if (state.state == States::MOVED) {
//             own->r->err(expr, "use of moved variable " + std::to_string(state.mv->line));
//         }
//         return;
//     }
//     auto fa = dynamic_cast<FieldAccess *>(expr);
//     if (fa) {
//         auto rt_scope = own->r->resolve(fa->scope);
//         if (rt_scope.type.isPointer() && own->isDropType(rt)) {
//             own->r->err(expr, "move field of ptr");
//         }
//         if (own->isDropType(rt_scope)) {
//             if (own->method->name == "drop" && own->method->self.has_value() && own->method->params.empty()) {
//                 return;
//             }
//             auto sd = dynamic_cast<StructDecl *>(rt.targetDecl);
//             /*if (sd->fields.size() == 1) {
//                 return;
//             }*/
//             //own->r->err(expr, "partial move not supported");
//         }
//         for (auto scp : own->rev_scopes()) {
//             for (auto &act : scp->actions) {
//                 if (!act.is_move()) {
//                     continue;
//                 }
//                 auto &mv = act.mv;
//                 auto rt_old = own->r->resolve(mv.rhs.expr);
//                 if (rt_old.vh.has_value() && rt_scope.vh.has_value() && rt_old.vh.value().id == rt_scope.vh.value().id) {
//                     if (!scp->ends_with_return) {
//                         own->r->err(expr, "assign field to moved variable, moved in " + std::to_string(mv.line));
//                     }
//                 }
//             }
//         }
//         return;
//     }
// }

bool is_lhs(Move &mv, Expression *expr, Ownership *own) {
    if (!mv.lhs.has_value()) return false;
    auto fa = dynamic_cast<FieldAccess *>(expr);
    if (fa) {
        auto fa_mv = dynamic_cast<FieldAccess *>(mv.lhs.value().expr);
        if (fa_mv) {
            return expr->print() == fa_mv->print();
        }
        return false;
    }
    auto rt = own->r->resolve(expr);
    if (!rt.vh.has_value()) {
        //expr can only be rhs, todo field access
        return false;
    }
    if (mv.lhs && mv.lhs->is_var()) {
        return mv.lhs->var_id == rt.vh->id;
    }
    //mv lhs not var, eg f.a
    return false;
}

bool is_lhs(Move &mv, const Lhs &lhs, Ownership *own) {
    if (lhs.is_var()) {
        if (!mv.lhs->is_var()) return false;
        return lhs.var_id == mv.lhs->var_id;
    }
    return is_lhs(mv, lhs.expr, own);
}

bool is_rhs(Move &mv, Expression *expr, Ownership *own) {
    auto rt = own->r->resolve(mv.rhs.expr);
    auto rt_expr = own->r->resolve(expr);
    if (rt.vh) {
        if (rt_expr.vh) {
            return rt.vh->id == rt_expr.vh->id;
        }
        return false;
    }
    auto fa = dynamic_cast<FieldAccess *>(expr);
    if (fa) {
        auto fa_mv = dynamic_cast<FieldAccess *>(mv.rhs.expr);
        if (fa_mv) {
            return expr->print() == mv.rhs.expr->print();
        }
        return false;
    }
    return expr->id == mv.rhs.id;
}

bool is_rhs(Move &mv, const Lhs &rhs, Ownership *own) {
    if (rhs.is_var()) {
        auto rt_mv = own->r->resolve(mv.rhs.expr);
        return rt_mv.vh && rt_mv.vh->id == rhs.var_id;
    }
    return is_rhs(mv, rhs.expr, own);
}

State get_state(const Lhs &lhs, Move &mv, Ownership *own) {
    State res{States::NONE, nullptr};
    if (is_rhs(mv, lhs, own)) {//move
        res.mv = &mv;
        res.state = States::MOVED;
    }
    if (is_lhs(mv, lhs, own)) {//reassign
        res.mv = &mv;
        res.state = States::ASSIGNED;
    }
    return res;
}

State get_state(const Lhs &lhs, VarScope &scope, Ownership *own, bool use_return, std::set<int> &done, bool look_parent) {
    if (use_return && scope.exit.is_return()) return State{States::NONE, nullptr};
    for (auto act : rev(scope.actions)) {
        if (act->is_move()) {
            auto &mv = act->mv;
            State tmp = get_state(lhs, mv, own);
            if (!tmp.is_none()) {
                return tmp;
            }
            continue;
        }
        if (done.contains(act->scope_decl)) {
            //prevent infinite recursion between child and parent
            continue;
        }
        auto ch_scope = own->getScope(act->scope_decl);
        auto tmp = get_state(lhs, ch_scope, own, use_return, done, false);
        if (tmp.is_none()) {
            continue;
        }
        // if (ch_scope.type == ScopeId::ELSE) {
        //     auto &then = own->getScope(ch_scope.sibling);
        //     auto if_state = get_state(v, then, own, use_return);
        //     if (if_state.state == States::ASSIGNED) {
        //         if (tmp.state == States::MOVED) {
        //             //tmp dominates
        //         } else {//both assign
        //         }
        //     } else if (if_state.state == States::MOVED) {
        //         if (tmp.state == States::ASSIGNED) {
        //             //if_state dominates
        //             return if_state;
        //         } else {//both move
        //         }
        //     }
        // }
        return tmp;
    }
    if (scope.type == ScopeId::ELSE) {
        //ignore sibling's move
        done.insert(scope.sibling);
    }
    if (scope.parent != -1 && look_parent) {
        done.insert(scope.id);
        auto parent = own->getScope(scope.parent);
        return get_state(lhs, parent, own, use_return, done, look_parent);
    }
    State res{States::NONE, nullptr};
    return res;
}

bool isMoved(Variable &v, VarScope &scope, Ownership *own, bool use_return, bool look_parent) {
    std::set<int> done;
    auto state = get_state(Lhs(nullptr, v.id), scope, own, use_return, done, look_parent);
    return state.is_moved();
}
bool isMoved(Expression *expr, VarScope &scope, Ownership *own, bool use_return, bool look_parent) {
    std::set<int> done;
    auto state = get_state(Lhs(expr), scope, own, use_return, done, look_parent);
    return state.is_moved();
}
bool isMoved(Variable &v, VarScope &scope, Ownership *own, bool use_return) {
    return isMoved(v, scope, own, use_return, true);
}

void Ownership::check_assignable(Expression *expr) {
    auto de = dynamic_cast<DerefExpr *>(expr);
    if (de) {
        return;
    }
    auto fa = dynamic_cast<FieldAccess *>(expr);
    if (fa) {
        auto rt = r->resolve(expr);
        auto rt_scope = r->resolve(fa->scope);
        if (rt_scope.type.isPointer() && DropHelper::isDropType(rt, r)) {
            //r->err(expr, "move field of ptr");
        }
        if (DropHelper::isDropType(rt_scope, r)) {
            //r->err(expr, "partial move");
        }
        auto state = get_state(Lhs(fa->scope), *last_scope, this, true);
        if (state.is_moved()) {
            r->err(expr, "assign to field of moved variable, moved in " + std::to_string(state.mv->line));
        } else if (state.is_moved_partial()) {
            r->err(expr, "assign to field of partially moved variable, moved in " + std::to_string(state.mv->line));
        }
    }
}

void Ownership::beginAssign(Expression *lhs, llvm::Value *ptr) {
    if (lhs == nullptr) return;
    if (verbose) std::cout << "beginAssign " << lhs->print() << " line: " << lhs->line << std::endl;
    check_assignable(lhs);
    if (!isDropType(lhs)) return;
    drop(lhs, ptr);
}

void Ownership::endAssign(Expression *lhs, Expression *rhs) {
    if (!isDropType(rhs)) return;
    //is_movable(rhs, this);
    auto de = dynamic_cast<DerefExpr *>(lhs);
    if (de) {
        last_scope->actions.push_back(Action(Move::make_transfer(Object::make(rhs))));
        return;
    }
    auto lhs_rt = r->resolve(lhs);
    if (lhs_rt.vh) {
        auto &v = getVar(lhs_rt.vh->id);
        last_scope->actions.push_back(Action(Move::make_var_move(lhs, &v, Object::make(rhs))));
    } else {
        last_scope->actions.push_back(Action(Move::make_var_move(lhs, Object::make(rhs))));
    }
}

void Ownership::doMoveReturn(Expression *expr) {
    check(expr);
    last_scope->actions.push_back(Action(Move::make_transfer(Object::make(expr))));
}

//?.name = expr
void Ownership::moveToField(Expression *expr) {
    doMoveCall(expr);
}

void Ownership::doMoveCall(Expression *arg) {
    if (!isDropType(arg)) return;
    check(arg);
    last_scope->actions.push_back(Action(Move::make_transfer(Object::make(arg))));
}

void Ownership::call_drop(Type &type, llvm::Value *ptr) {
    if (!enabled) {
        return;
    }
    call_drop_force(type, ptr);
}

void Ownership::call_drop_force(Type &type, llvm::Value *ptr) {
    protos.call_drop_force(type, ptr);
}

void drop_info(Variable &v, const std::string &msg) {
    print("drop var " + v.name + ":" + v.type.print() + " line: " + std::to_string(v.line) + " " + msg);
    if (v.name == "sig_res" && v.line == 687) {
        int xx = 5;
    }
}
void drop_info(Expression *expr) {
    print("drop " + expr->print() + " line: " + std::to_string(expr->line));
    if (expr->print() == "res.parent" && expr->line == 725) {
        int xx = 5;
    }
}

void Ownership::drop(Variable &v) {
    if (verbose) print("drop " + v.print());
    if (v.is_self && is_drop_method(*method)) {
        //prevent recursion of drop self
        return;
    }
    call_drop(v.type, v.ptr);
}

void Ownership::drop(Expression *expr, llvm::Value *ptr) {
    auto rt = r->resolve(expr);
    DropHelper helper(r);
    if (!helper.isDrop(rt.targetDecl)) return;
    // if (!rt.vh.has_value()) {
    //     auto fa = dynamic_cast<FieldAccess *>(expr);
    //     if (fa) {
    //         if (verbose) {
    //             print("drop " + fa->print());
    //         }
    //         drop_info(expr);
    //         call_drop(rt.type, ptr);
    //         return;
    //     }
    //     compiler->resolv->err(expr, " drop obj not var");
    // }
    if (verbose) std::cout << "drop expr " << expr->print() << "\n";
    // auto de = dynamic_cast<DerefExpr *>(expr);
    // if (de) {
    //     //auto rt2 = r->resolve(de->expr);
    //     drop_info(expr);
    //     call_drop(rt.type, ptr);
    //     return;
    // }
    if (isMoved(expr, *last_scope, this, true, true)) {
        return;
    }
    call_drop(rt.type, ptr);
}


bool is_declared_in(Variable &v, VarScope &scope, Ownership *own) {
    for (auto v2 : scope.vars) {
        if (v2 == v.id) {
            return true;
        }
    }
    for (auto act : scope.actions) {
        if (!act.is_scope_decl()) continue;
        auto ch = act.scope_decl;
        auto ch_scope = own->getScope(ch);
        if (is_declared_in(v, ch_scope, own)) {
            return true;
        }
    }
    return false;
}

std::vector<Variable *> get_outer_vars(VarScope &scope, Ownership *own) {
    std::vector<Variable *> vars;
    auto cur_id = scope.parent;
    while (cur_id != -1) {
        auto cur = own->getScope(cur_id);
        for (auto v_id : cur.vars) {
            auto &v = own->getVar(v_id);
            vars.push_back(&v);
        }
        cur_id = cur.parent;
    }
    return vars;
}

void drop_objects(VarScope &scope, Ownership *own) {
    for (auto &obj : scope.objects) {
        //todo is valid
        bool is_moved = false;
        for (auto &act : scope.actions) {
            if (!act.is_move()) continue;
            if (act.mv.rhs.id == obj.id) {
                is_moved = true;
                break;
            }
        }
        if (!is_moved) {
            auto rt = own->r->resolve(obj.expr);
            //drop(obj.expr, obj.ptr);
            if (verbose) {
                std::cout << "drop obj" << obj.expr->print() << " line: " << obj.expr->line << "\n";
            }
            drop_info(obj.expr);
            own->call_drop(rt.type, obj.ptr);
        }
    }
}

//drop vars in this scope
void Ownership::endScope(VarScope &scope) {
    if (verbose) print("endscope " + printMethod(method) + " " + scope.print_info());
    if (scope.type == ScopeId::MAIN) {
        //doReturn(scope.line);
        //return;
        if (verbose) std::cout << std::endl;
    }
    drop_objects(scope, this);
    for (auto v_id : scope.vars) {
        auto &v = getVar(v_id);
        if (v.is_self && is_drop_method(*method)) {
            //prevent recursion of drop self
            continue;
        }
        if (v.name == "sig_res") {
            auto x = 55;
        }
        if (!isMoved(v, scope, this, true)) {
            drop_info(v, "endScope:" + scope.print_info());
            drop(v);
        }
    }
}

//if sibling moves outer var, we must drop it
void Ownership::end_branch(VarScope &branch) {
    //doReturn already drops
    if (branch.exit.is_return()) return;
    if (verbose) print("end_branch " + printMethod(method) + " " + branch.print_info());
    auto &sibling = getScope(branch.sibling);
    //if then_scope drops&moves outer var, else_scope must drop it too, and vice versa
    auto outers = get_outer_vars(branch, this);
    for (auto v : outers) {
        if (v->is_self && is_drop_method(*method)) {
            //prevent recursion of drop self
            continue;
        }
        if (isMoved(*v, sibling, this, true, false) && !isMoved(*v, branch, this, true, false)) {
            //transferred, so drop
            drop_info(*v, "end_branch:" + branch.print_info());
            drop(*v);
        }
    }
    drop_objects(branch, this);
}

//cleans all vars
void Ownership::doReturn(int line) {
    if (verbose) print("doReturn " + printMethod(method) + " line: " + std::to_string(line));
    auto vars = get_outer_vars(*last_scope, this);
    for (auto v : vars) {
        if (!isMoved(*v, *last_scope, this, false)) {
            drop(*v);
        }
    }
    //drop local
    for (auto v_id : last_scope->vars) {
        auto &v = getVar(v_id);
        if (v.is_self && is_drop_method(*method)) {
            //prevent recursion of drop self
            continue;
        }
        if (!isMoved(v, *last_scope, this, false)) {
            drop_info(v, "return:" + std::to_string(line));
            drop(v);
        }
    }
    //todo all scopes
    drop_objects(*last_scope, this);
}

//drop all up to closest loop
void Ownership::jump_continue() {
}

void Ownership::jump_break() {
}
