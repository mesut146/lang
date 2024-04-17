#include "Ownership.h"
#include "Compiler.h"
#include "MethodResolver.h"

int VarScope::last_id = 0;

bool verbose = false;

template<class T>
std::vector<T *> rev(std::vector<T> &vec) {
    std::vector<T *> res;
    for (int i = vec.size() - 1; i >= 0; --i) {
        res.push_back(&vec[i]);
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
/*Ownership::Ownership(Compiler *compiler, Method *m) : compiler(compiler), method(m) {
    this->r = compiler->resolv.get();
    this->last_scope = nullptr;
}*/

void Ownership::init(Compiler *c) {
    this->compiler = c;
    this->r = compiler->resolv.get();
    this->protos.clear();
    scope_map.clear();
    var_map.clear();
    drop_impls.clear();
}

void Ownership::init(Method *m) {
    //clear prev method
    scope_map.clear();
    var_map.clear();

    this->method = m;
    auto ms = VarScope(ScopeId::MAIN, ++VarScope::last_id);
    ms.line = m->line;
    scope_map.insert({ms.id, ms});
    this->main_scope = &scope_map.at(ms.id);
    this->last_scope = main_scope;
}

bool Ownership::isDrop(BaseDecl *decl) {
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

void Ownership::addPtr(Expression *expr, llvm::Value *ptr) {
    if (!last_scope) {
        throw std::runtime_error("Ownership::addPtr");
    }
    auto rt = r->resolve(expr);
    if (isDropType(rt)) {
        last_scope->objects.push_back(Object::make(expr, ptr));
    }
}

Variable *Ownership::add(std::string &name, Type &type, llvm::Value *ptr, int id, int line) {
    auto rt = r->resolve(type);
    /*if (type.isPointer()) {
        ptr = compiler->Builder->CreateLoad(llvm::PointerType::get(compiler->ctx(), 0), ptr);
        return add(name, *type.scope.get(), ptr, id, line);
    }*/
    if (!isDropType(rt)) return nullptr;
    if (id == -1) {
        throw std::runtime_error("Ownership::add id");
    }
    var_map.insert({id, Variable(name, type, ptr, id, line, last_scope->id)});
    last_scope->vars.push_back(id);
    return &var_map.at(id);
}

void Ownership::check(Expression *expr) {
    for (auto &mv : last_scope->moves) {
        if (mv.rhs.id == expr->id) {
            r->err(expr, "use after move, line: " + std::to_string(mv.line));
        }
    }
    is_movable(expr, this);
}

void is_movable(Expression *expr, Ownership *own) {
    auto rt = own->r->resolve(expr);
    if (!own->isDropType(rt)) return;
    auto de = dynamic_cast<DerefExpr *>(expr);
    if (de) {
        own->r->err(expr, "can't move by deref");
    }
    if (rt.vh) {
        if (rt.type.isPointer()) {
            return;
        }
        auto &v = own->getVar(rt.vh->id);
        if (isMoved(v, *own->last_scope, own, true)) {
            own->r->err(expr, "use of moved variable " + std::to_string(v.line));
        }
        return;
    }
    auto fa = dynamic_cast<FieldAccess *>(expr);
    if (fa) {
        auto rt_scope = own->r->resolve(fa->scope);
        if (rt_scope.type.isPointer() && own->isDropType(rt)) {
            own->r->err(expr, "move field of ptr");
        }
        if (own->isDropType(rt_scope)) {
            own->r->err(expr, "partial move not supported");
        }
        for (auto scp : own->rev_scopes()) {
            for (auto &mv : scp->moves) {
                auto rt_old = own->r->resolve(mv.rhs.expr);
                if (rt_old.vh.has_value() && rt_scope.vh.has_value() && rt_old.vh.value().id == rt_scope.vh.value().id) {
                    if (!scp->ends_with_return) {
                        own->r->err(expr, "assign field to moved variable, moved in " + std::to_string(mv.line));
                    }
                }
            }
        }
        return;
    }
}

bool is_lhs(Move &mv, Variable &v, Ownership *own) {
    if (mv.lhs) {
        return mv.lhs->id == v.id;
    }
    if (mv.lhs_expr) {
        auto rt = own->r->resolve(mv.lhs_expr);
        return rt.vh && rt.vh->id == v.id;
    }
    return false;
}

bool is_rhs(Move &mv, Variable &v, Ownership *own) {
    auto rt = own->r->resolve(mv.rhs.expr);
    return rt.vh && rt.vh->id == v.id;
}

State get_state(Variable &v, VarScope &scope, Ownership *own, bool use_return) {
    if (use_return && scope.ends_with_return) return State{States::NONE, nullptr};
    State res{States::NONE, nullptr};
    bool has_state = false;
    for (auto mv : rev(scope.moves)) {
        if (is_rhs(*mv, v, own)) {//move
            res.mv = mv;
            res.state = States::MOVED;
            has_state = true;
            break;
        }
        if (is_lhs(*mv, v, own)) {//reassign
            res.mv = mv;
            res.state = States::ASSIGNED;
            has_state = true;
            break;
        }
    }
    //first look child scopes
    for (auto scp_id : rev(scope.scopes)) {
        auto ch_scope = own->getScope(*scp_id);
        auto tmp = get_state(v, ch_scope, own, use_return);
        if (tmp.state == States::NONE) {
            continue;
        }
        if (ch_scope.type == ScopeId::ELSE) {
            auto &then = own->getScope(ch_scope.sibling);
            auto if_state = get_state(v, then, own, use_return);
            if (if_state.state == States::ASSIGNED) {
                if (tmp.state == States::MOVED) {
                    //tmp dominates
                } else {//both assign
                }
            } else if (if_state.state == States::MOVED) {
                if (tmp.state == States::ASSIGNED) {
                    //if_state dominates
                    tmp = if_state;
                    has_state = true;
                } else {//both move
                }
            }
        }
        if (!has_state) return tmp;
        if (tmp.mv->line > res.mv->line) {
            return tmp;
        } else {
            return res;
        }
    }
    //then look parent scopes
    return res;
}

bool isMoved(Variable &v, VarScope &scope, Ownership *own, bool use_return) {
    // auto mv = get_last_move(v, scope, own, use_return);
    // if (mv) {
    //     return is_rhs(*mv, v, own);
    // }
    auto state = get_state(v, scope, own, use_return);
    return state.state == States::MOVED;
}

// void Ownership::doMove(Expression *expr) {
//     if (true) return;
//     auto rt = r->resolve(expr);
//     if (!isDropType(rt)) return;
//     auto sn = dynamic_cast<SimpleName *>(expr);
//     if (sn) {
//         check(expr);
//         //auto id = rt.vh.value().id;
//         return;
//     }
//     auto fa = dynamic_cast<FieldAccess *>(expr);
//     if (fa) {
//         auto scp = r->resolve(fa->scope);
//         if (scp.type.isPointer()) {
//             r->err(expr, "move field of ptr");
//         }
//         if (isDropType(scp)) {
//             r->err(expr, "partial move");
//         }
//         doMove(fa->scope);
//         //r->err(expr, "domove");
//         return;
//     }
// }

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

std::pair<Move *, VarScope *> Ownership::is_assignable(Expression *expr) {
    auto de = dynamic_cast<DerefExpr *>(expr);
    if (de) {
        auto rt = r->resolve(expr);
        if (isDropType(rt)) {
        }
        return {nullptr, nullptr};
    }
    auto fa = dynamic_cast<FieldAccess *>(expr);
    if (fa) {
        auto rt = r->resolve(expr);
        auto rt_scope = r->resolve(fa->scope);
        if (rt_scope.type.isPointer() && isDropType(rt)) {
            //r->err(expr, "move field of ptr");
        }
        if (isDropType(rt_scope)) {
            //r->err(expr, "partial move");
        }
        //todo use get_state
        for (auto scp : rev_scopes()) {
            for (auto &mv : scp->moves) {
                auto rt_old = r->resolve(mv.rhs.expr);
                if (rt_old.vh.has_value() && rt_scope.vh.has_value() && rt_old.vh.value().id == rt_scope.vh.value().id) {
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

void Ownership::beginAssign(Expression *lhs, llvm::Value *ptr) {
    if (verbose) std::cout << "beginAssign " << lhs->print() << " line: " << lhs->line << std::endl;
    is_assignable(lhs);
    auto rt = r->resolve(lhs);
    if (!isDropType(rt)) return;
    drop(lhs, ptr);
}

void Ownership::endAssign(Expression *lhs, Expression *rhs) {
    auto rt = r->resolve(rhs);
    if (!isDropType(rt)) return;
    is_movable(rhs, this);
    auto de = dynamic_cast<DerefExpr *>(lhs);
    if (de) {
        last_scope->moves.push_back(Move::make_transfer(Object::make(rhs)));
        return;
    }
    auto rt_lhs = r->resolve(lhs);
    //auto v = getVar(this, lhs);
    if (rt_lhs.vh) {
        auto &v = getVar(rt_lhs.vh->id);
        last_scope->moves.push_back(Move::make_var_move(&v, Object::make(rhs)));
    } else {
        last_scope->moves.push_back(Move::make_var_move(lhs, Object::make(rhs)));
    }
}

void Ownership::doMoveReturn(Expression *expr) {
    check(expr);
    last_scope->moves.push_back(Move::make_transfer(Object::make(expr)));
}

//?.name = expr
void Ownership::moveToField(Expression *expr) {
    doMoveCall(expr);
}

void Ownership::doMoveCall(Expression *arg) {
    auto rt = r->resolve(arg);
    if (!isDropType(rt)) return;
    is_movable(arg, this);
    //last_scope->actions.push_back(Action(Move::make_transfer(Object::make(arg))));
    last_scope->moves.push_back(Move::make_transfer(Object::make(arg)));
}

/*std::map<std::string, Type> make_map(const Type &type, Compiler *c) {
    std::map<std::string, Type> res;
    auto rt = c->resolv->resolve(type);
    if (!rt.targetDecl) {
        c->resolv->err(&type, "cant make map");
    }
    return res;
}*/


MethodCall make_drop_mc(Compiler *c, Expression *expr) {
    //{expr}.drop()
    MethodCall mc;
    mc.id = ++Node::last_id;
    mc.scope.reset(expr);
    mc.name = "drop";
    return mc;
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
        //generic
        /*MethodResolver mr(c->resolv.get());
        std::map<std::string, Type> map;
        int i = 0;
        for (auto &ta : impl->type.typeArgs) {
            map[ta.name] = type.typeArgs.at(i);
            ++i;
        }
        MethodCall mc;
        mc.name = "drop";
        mc.scope.reset(new Type("Drop"));
        mc.is_static = true;
        auto sig = Signature::make(&mc, c->resolv.get());
        //return mr.generateMethod(map, m, sig);
        Generator gen(map);
        auto res = std::any_cast<Method *>(gen.visitMethod(m));
        res->used_path = c->resolv->unit->path;
        return res;*/
    }
    return nullptr;
}

Method *findDrop(Ownership *own, const Type &type) {
    auto c = own->compiler;
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
    /*auto imp = c->resolv->derive_drop(rt.targetDecl);
    own->drop_impls.push_back(std::move(imp));
    auto imp2 = dynamic_cast<Impl *>(own->drop_impls.back().get());
    return &imp2->methods.at(0);*/
}

void dump_proto(llvm::Function *proto) {
    //std::cout << proto->getName().data() << " = " << std::endl;
    //proto->dump();
}

void Ownership::call_drop(Type &type, llvm::Value *ptr) {
    llvm::Function *proto = nullptr;
    //todo, separate from compiler protos
    if (protos.contains(type.print())) {
        proto = protos[type.print()];
        dump_proto(proto);
    } else {
        auto drop_method = findDrop(this, type);
        auto mangled = mangle(drop_method);
        if (compiler->funcMap.contains(mangled)) {
            proto = compiler->funcMap[mangled];
            dump_proto(proto);
        } else {
            proto = compiler->make_proto(drop_method);
            dump_proto(proto);
        }
        protos[type.print()] = proto;
    }
    std::vector<llvm::Value *> args{ptr};
    compiler->loc(0, 0);
    compiler->Builder->CreateCall(proto, args);
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

bool is_drop_method(Method &m) {
    return m.name == "drop" &&
           m.parent.is_impl() &&
           m.parent.trait_type.has_value() &&
           m.parent.trait_type->print() == "Drop";
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
    if (!isDrop(rt.targetDecl)) return;
    if (!rt.vh.has_value()) {
        auto fa = dynamic_cast<FieldAccess *>(expr);
        if (fa) {
            if (verbose) {
                print("drop " + fa->print());
            }
            call_drop(rt.type, ptr);
            return;
        }
        compiler->resolv->err(expr, " drop obj not var");
    }
    if (verbose) std::cout << "drop expr " << expr->print() << "\n";
    auto de = dynamic_cast<DerefExpr *>(expr);
    if (de) {
        //auto rt2 = r->resolve(de->expr);
        call_drop(rt.type, ptr);
        return;
    }
    //todo use get_state
    Variable *v = &getVar(rt.vh->id);
    auto last_mv = get_move(this, *v, *last_scope);
    if (!last_mv) {//nothing, just drop
        drop(*v);
    } else if (is_moved_to(*last_mv, *v, r)) {//moved and reassign, drop
        drop(*v);
    } else {
        //moved from, reassign, no drop
    }
}


Move *get_last_move(Variable &v, VarScope &scope, Ownership *own, bool use_return) {
    if (use_return && scope.ends_with_return) return nullptr;
    Move *res = nullptr;
    for (auto mv : rev(scope.moves)) {
        if (is_rhs(*mv, v, own)) {//move
            res = mv;
            break;
        }
        if (is_lhs(*mv, v, own)) {//reassign
            res = mv;
            break;
        }
    }
    for (auto scp_id : rev(scope.scopes)) {
        auto ch_scope = own->getScope(*scp_id);
        auto tmp = get_last_move(v, ch_scope, own, use_return);
        if (!tmp) continue;
        if (ch_scope.type == ScopeId::ELSE) {
            auto &then = own->getScope(ch_scope.sibling);
            auto mv2 = get_last_move(v, then, own, use_return);
            if (mv2) {
                if (is_rhs(*tmp, v, own)) return tmp;
                if (mv2 && is_rhs(*mv2, v, own)) {
                }
            }
        }
        if (!res) return tmp;
        if (tmp->line > res->line) {
            return tmp;
        } else {
            return res;
        }
    }
    return res;
}

std::string print_type(const VarScope &scope) {
    if (scope.type == ScopeId::MAIN) {
        return "ScopeId::MAIN";
    }
    if (scope.type == ScopeId::IF) {
        return "ScopeId::IF";
    }
    if (scope.type == ScopeId::ELSE) {
        return "ScopeId::ELSE";
    }
    if (scope.type == ScopeId::WHILE) {
        return "ScopeId::WHILE";
    }
    if (scope.type == ScopeId::FOR) {
        return "ScopeId::FOR";
    }
    throw std::runtime_error("type");
}


bool is_declared_in(Variable &v, VarScope &scope, Ownership *own) {
    for (auto v2 : scope.vars) {
        if (v2 == v.id) {
            return true;
        }
    }
    for (auto ch : scope.scopes) {
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
        for (auto &mv : scope.moves) {
            if (mv.rhs.id == obj.id) {
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
            own->call_drop(rt.type, obj.ptr);
        }
    }
}

//drop vars in this scope
void Ownership::endScope(VarScope &scope) {
    if (verbose) print("endscope " + printMethod(method) + " " + print_type(scope) + " line: " + std::to_string(scope.line));
    if (scope.type == ScopeId::MAIN) {
        //doReturn(scope.line);
        //return;
        if (verbose) std::cout << std::endl;
    }
    drop_objects(scope, this);
    for (auto v_id : scope.vars) {
        auto &v = getVar(v_id);
        if (!isMoved(v, scope, this, true)) {
            drop(v);
        }
    }
}

//if sibling moves outer var, we must drop it
void Ownership::end_branch(VarScope &branch) {
    if (verbose) print("end_branch " + printMethod(method) + " " + print_type(branch) + " line: " + std::to_string(branch.line));
    auto &sibling = getScope(branch.sibling);
    //if then_scope drops var, else_scope must drop it too
    auto outers = get_outer_vars(branch, this);
    for (auto v : outers) {
        if (isMoved(*v, sibling, this, true) && !isMoved(*v, branch, this, true)) {
            //transferred, so drop
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
        if (!isMoved(v, *last_scope, this, false)) {
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
