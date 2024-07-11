import parser/ast
import parser/bridge
import parser/utils
import parser/own_visitor
import parser/compiler
import parser/resolver
import parser/compiler_helper
import parser/method_resolver
import parser/debug_helper
import parser/printer
import parser/derive
import std/map
import std/stack

static last_scope: i32 = 0;
static verbose: bool = true;
static print_drop: bool = true;
static print_check: bool = false;

func is_drop_method(method: Method*): bool{
    if(method.name.eq("drop") && method.parent.is_impl()){
        let imp =  method.parent.as_impl();
        return imp.trait_name.is_some() && imp.trait_name.get().eq("Drop");
    }
    return false;
}

//prm or var
struct Variable {
    name: String;
    type: Type;
    ptr: Value*;
    id: i32;
    line: i32;
    scope: i32;
    is_self: bool;
}
impl Variable{
    func clone(self): Variable{
        return Variable{
            name: self.name.clone(),
            type: self.type.clone(),
            ptr: self.ptr,
            id: self.id,
            line: self.line,
            scope: self.scope,
            is_self: self.is_self
        };
    }
}

//dropable
#derive(Debug)
struct Object {
    expr: Expr*;
    ptr: Value*;
    id: i32;          //prm
    name: String;     //prm
    scope: i32;
}
#derive(Debug)
enum ScopeType {
    MAIN,
    IF,
    ELSE,
    WHILE,
    FOR
}
struct VarScope{
    kind: ScopeType;
    id: i32;
    line: i32;
    vars: List<i32>;
    objects: List<Object>;
    actions: List<Action>;
    exit: Exit;
    parent: i32;
    sibling: i32;
    state_map: Map<Rhs, StateType>; //var_id -> StateType
    pending_parent: Map<i32, StateType>; //var_id -> StateType
}

#derive(Debug)
enum StateType {
    NONE,
    MOVED(line: i32),
    MOVED_PARTIAL,
    ASSIGNED
}

#derive(Debug)
struct State{
    kind: StateType;
    scope: VarScope*;
}

enum Action {
    MOVE(mv: Move),
    SCOPE(id: i32, line: i32)
}
struct Move{
    lhs: Option<Moved>;
    rhs: Moved;
    line: i32;
}
struct Moved{
    expr: Expr*;
    var: Option<Variable>;
    //field: Option<String>;
}

enum Rhs{
    EXPR(e: Expr*),
    VAR(v: Variable),
    FIELD(scp: Variable, name: String)
}

impl State{
    func new(kind: StateType, scope: VarScope*): State{
        return State{kind, scope};
    }
    func is_moved(self): bool{
        return self.kind is StateType::MOVED || self.kind is StateType::MOVED_PARTIAL;
    }
    func is_assigned(self): bool{
        return self.kind is StateType::ASSIGNED;
    }
    func is_none(self): bool{
        return self.kind is StateType::NONE;
    }
}
impl StateType{
    func is_moved(self): bool{
        return self is StateType::MOVED || self is StateType::MOVED_PARTIAL;
    }
    func is_assigned(self): bool{
        return self is StateType::ASSIGNED;
    }
    func is_none(self): bool{
        return self is StateType::NONE;
    }
}

impl Moved{
    func new(expr: Expr*, own: Own*): Moved{
        /*if let Expr::Access(scp*, name*)=(expr){
            let scp_rt = own.compiler.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_some()){
                let scp_var = own.get_var(scp_rt.vh.get().id);
                return Moved{expr, Option::new(scp_var.clone())};
            }
        }*/
        let rt = own.compiler.get_resolver().visit(expr);
        if(rt.vh.is_some()){
            let var = own.get_var(rt.vh.get().id);
            return Moved{expr, Option::new(var.clone())};
        }
        return Moved{expr, Option<Variable>::new()};
    }
}

impl Rhs{
    func new(expr: Expr*, own: Own*): Rhs{
        if let Expr::Access(scp*, name*)=(expr){
            let scp_rt = own.compiler.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_some()){
                let scp_var = own.get_var(scp_rt.vh.get().id);
                return Rhs::FIELD{scp_var.clone(), name.clone()};
            }
        }
        let rt = own.compiler.get_resolver().visit(expr);
        if(rt.vh.is_some() && (expr is Expr::Name || expr is Expr::Unary)){
            let var = own.get_var(rt.vh.get().id);
            return Rhs::VAR{var.clone()};
        }
        return Rhs::EXPR{expr};
    }
    func new(var: Variable): Rhs{
        return Rhs::VAR{var};
    }
    func get_var(self): Variable*{
        if let Rhs::VAR(v*)=(self){
            return v;
        }
        panic("");
    }
    func get_expr(self): Expr*{
        if let Rhs::EXPR(e)=(self){
            return e;
        }
        panic("");
    }
    func get_id(self): i32{
        if let Rhs::EXPR(e)=(self){
            return e.id;
        }
        if let Rhs::VAR(v)=(self){
            return v.id;
        }
        panic("{}", self);
    }
    func is_vh(self, vh: VarHolder*, resolver: Resolver*): bool{
        if let Rhs::EXPR(e)=(self){
            let rt = resolver.visit(e);
            if(rt.vh.is_some()){
                let res = rt.vh.get().id == vh.id;
                rt.drop();
                return res;
            }
            rt.drop();
            return false;
        }
        return self.get_var().id == vh.id;
    }
    func eq(self, other: Moved*, resolver: Resolver*): bool{
        if let Rhs::EXPR(e)=(self){
            if(e.id == other.expr.id){
                return true;
            }
            return false;
        }
        if(other.var.is_some()){
            return self.get_var().id == other.var.get().id;
        }
        return false;
    }
}

impl Move{
    func is_lhs(self, lhs2: Rhs*, own: Own*): bool{
        if(self.lhs.is_none()){
            return false;
        }
        let lhs: Moved* = self.lhs.get();
        return lhs2.eq(lhs, own.compiler.get_resolver());
    }
    func is_rhs(self, other: Rhs*, own: Own*): bool{
        if(self.rhs.var.is_none()){
            if(other is Rhs::EXPR){
                return self.rhs.expr.id == other.get_expr().id;
            }
            return false;
        }
        //self is var
        if(other is Rhs::VAR){
            let var: Variable* = self.rhs.var.get();
            return var.id == other.get_var().id;
        }
        return false;
    }
}

impl VarScope{
    func new(kind: ScopeType, line: i32, exit: Exit): VarScope{
        let scope = VarScope{
            kind: kind,
            id: ++last_scope,
            line: line,
            vars: List<i32>::new(),
            objects: List<Object>::new(),
            actions: List<Action>::new(),
            exit: exit,
            parent: -1,
            sibling: -1,
            state_map: Map<Rhs, StateType>::new(),
            pending_parent: Map<i32, StateType>::new()
        };
        return scope;
    }
}

enum Droppable{
    VAR(var: Variable*),
    OBJ(obj: Object*)
}

struct Own{
    compiler: Compiler*;
    method: Method*;
    main_scope: i32;
    cur_scope: i32;
    scope_map: Map<i32, VarScope>;
    var_map: Map<i32, Variable>;
}

impl Own{
    func new(c: Compiler*, m: Method*): Own{
        let exit = Exit::get_exit_type(m.body.get());
        let main_scope = VarScope::new(ScopeType::MAIN, m.line, exit);
        let res = Own{
            compiler: c,
            method: m,
            main_scope: main_scope.id,
            cur_scope: main_scope.id,
            scope_map: Map<i32, VarScope>::new(),
            var_map: Map<i32, Variable>::new()
        };
        res.scope_map.add(main_scope.id, main_scope);
        return res;
    }
    func add_scope(self, kind: ScopeType, line: i32, exit: Exit): i32{
        if(verbose){
            print("add_scope {} line:{}\n", kind, line);
        }
        let scope = VarScope::new(kind, line, exit);
        let parent = self.get_scope();
        //copy parent states
        for(let i = 0;i < parent.state_map.len();++i){
            let pair = parent.state_map.get_pair_idx(i).unwrap();
            scope.state_map.add(pair.a.clone(), pair.b);
        }
        scope.parent = parent.id;
        let id = scope.id;
        self.scope_map.add(scope.id, scope);
        parent.actions.add(Action::SCOPE{id, line});        
        self.set_current(id);
        return id;
    }
    func add_scope(self, kind: ScopeType, stmt: Stmt*): i32{
        let exit = Exit::get_exit_type(stmt);
        return self.add_scope(kind, stmt.line, exit);
    }
    func add_scope(self, kind: ScopeType, stmt: Block*): i32{
        let exit = Exit::get_exit_type(stmt);
        return self.add_scope(kind, stmt.line, exit);
    }
    func set_current(self, id: i32){
        assert(id != -1);
        self.cur_scope = id;
    }
    func get_scope(self): VarScope*{
        return self.scope_map.get_ptr(&self.cur_scope).unwrap();
    }
    func get_scope(self, id: i32): VarScope*{
        return self.scope_map.get_ptr(&id).unwrap();
    }
    func get_var(self, id: i32): Variable*{
        let opt = self.var_map.get_ptr(&id);
        if(opt.is_none()){
            panic("var not found id={} scope={}", id, self.get_scope(self.main_scope).print(self));
        }
        return opt.unwrap();
    }
    func get_type(self, expr: Expr*): RType{
        let rt = self.compiler.get_resolver().visit(expr);
        return rt;
    }
    //register var & obj
    func is_drop_type(self, type: Type*): bool{
        let helper = DropHelper{self.compiler.get_resolver()};
        return helper.is_drop_type(type);
    }
    func is_drop_type(self, expr: Expr*): bool{
        let rt = self.get_type(expr);
        let res = self.is_drop_type(&rt.type);
        rt.drop();
        return res;
    }
    func is_drop_or_ptr(self, type: Type*): bool{
        if(type.is_pointer()){
            return self.is_drop_type(type.elem());
        }
        return self.is_drop_type(type);
    }
    func add_prm(self, p: Param*, ptr: Value*){
        //print("add_prm {}:{} line={}\n", p.name, p.type, p.line);
        dbg(p.name.eq("pp"), 22);
        if(!self.is_drop_or_ptr(&p.type)) return;
        let var = Variable{
            name: p.name.clone(),
            type: p.type.clone(),
            ptr: ptr,
            id: p.id,
            line: p.line,
            scope: self.get_scope().id,
            is_self: p.is_self
        };
        self.get_scope().vars.add(p.id);
        self.get_scope().state_map.add(Rhs::new(var.clone()), StateType::NONE);
        self.var_map.add(p.id, var);
    }
    func add_var(self, f: Fragment*, ptr: Value*){
        let rt = self.compiler.get_resolver().visit(f);
        if(!self.is_drop_or_ptr(&rt.type)){
            rt.drop();
            return;
        } 
        let var = Variable{
            name: f.name.clone(),
            type: rt.type.clone(),
            ptr: ptr,
            id: f.id,
            line: f.line,
            scope: self.get_scope().id,
            is_self: false
        };
        rt.drop();
        self.get_scope().vars.add(var.id);
        self.get_scope().state_map.add(Rhs::new(var.clone()), StateType::NONE);
        self.var_map.add(var.id, var);
        self.do_move(&f.rhs);
    }
    func add_iflet_var(self, arg: ArgBind*, fd: FieldDecl*, ptr: Value*){
        if(arg.is_ptr) return;
        if(!self.is_drop_type(&fd.type)) return;
        let var = Variable{
            name: arg.name.clone(),
            type: fd.type.clone(),
            ptr: ptr,
            id: arg.id,
            line: arg.line,
            scope: self.get_scope().id,
            is_self: false
        };
        self.get_scope().vars.add(var.id);
        self.get_scope().state_map.add(Rhs::new(var.clone()), StateType::NONE);
        self.var_map.add(var.id, var);
    }
    func add_obj(self, expr: Expr*, ptr: Value*, type: Type*){
        if(!self.is_drop_type(type)) return;
        let obj = Object{
            expr: expr,
            ptr: ptr,
            id: expr.id,
            name: expr.print(),
            scope: self.cur_scope
        };
        self.get_scope().objects.add(obj);
        self.get_scope().state_map.add(Rhs::new(expr, self), StateType::NONE);
    }

    func do_move(self, expr: Expr*){
        let rt = self.get_type(expr);
        if(!self.is_drop_type(&rt.type)){
            rt.drop();
            return;
        }
        let mv = Move{
            lhs: Option<Moved>::new(),
            rhs: Moved::new(expr, self),
            line: expr.line
        };
        let act = Action::MOVE{mv};
        if(verbose){
            print("do_move {}\n", act);
        }
        let scope = self.get_scope();
        scope.actions.add(act);
        self.update_state(expr, &rt, StateType::MOVED{expr.line}, scope);
        rt.drop();
    }
    //move rhs
    func do_assign(self, lhs: Expr*, rhs: Expr*){
        let scope = self.get_scope();
        let rt = self.get_type(rhs);
        if(!self.is_drop_type(&rt.type)){
            rt.drop();
            return;
        }
        let mv = Move{Option::new(Moved::new(lhs, self)), Moved::new(rhs, self), lhs.line};
        if(verbose){
            print("do_move {} line:{}\n", mv, lhs.line);
        }
        scope.actions.add(Action::MOVE{mv});
        self.update_state(rhs, &rt, StateType::MOVED{rhs.line}, scope);
        let rt_lhs = self.get_type(lhs);
        self.update_state(lhs, &rt_lhs, StateType::ASSIGNED, scope);
        rt.drop();
        rt_lhs.drop();
    }

    func update_state(self, expr: Expr*, rt: RType*, kind: StateType, scope: VarScope*){
        //scope.pending_parent.add(rt.vh.get().id, kind);
        let rhs = Rhs::new(expr, self);
        //set parent partially moved
        if let Rhs::FIELD(scp*, name*) = (&rhs){
            let scp_rhs = Rhs::new(scp.clone());
            self.update_state(scp_rhs, StateType::MOVED_PARTIAL, scope);
        }
        scope.state_map.add(rhs, kind);
        if(rt.vh.is_some()){
            //scope.state_map.add(rt.vh.get().id, kind);
            /*if(scope.parent != -1 && !(scope.kind is ScopeType::IF || scope.kind is ScopeType::ELSE)){
                let parent = self.get_scope(scope.parent);
                self.update_state(expr, rt, kind, parent);
            }*/
        }else{
        }
    }
    func update_state(self, rhs: Rhs, kind: StateType, scope: VarScope*){
        scope.state_map.add(rhs, kind);
    }
    func update_parent_state(self){
        //let parent = self.get_scope(scope.parent);
        //self.update_state(expr, rt, kind, parent);
    }
    func check(self, expr: Expr*){
        let rt = self.get_type(expr);
        if(!self.is_drop_type(&rt.type)){
            rt.drop();
            return;
        }
        rt.drop();
        let scope = self.get_scope();
        let rhs = Rhs::new(expr, self);
        dbg(expr.line == 266, 100);
        if(print_check){
            print("check {} line:{}\n", expr, expr.line);
        }
        dbg(expr.line == 35 && expr.print().eq("aa"), 100);
        let state = self.get_state(rhs, scope, true);
        if let StateType::MOVED(line)=(state.kind){
            print("{}\n", self.get_scope(self.main_scope).print(self));
            self.compiler.get_resolver().err(expr, format("use after move in {}:{}", printMethod(self.method), line));
        }
    }
    func check_field(self, expr: Expr*){
        if let Expr::Access(scp*,name*)=(expr){
            //scope could be partially moved, check right right field is valid
        }else{
            panic("check_field not field access {}", expr);
        }
    }

    func get_state(self, rhs: Rhs, scope: VarScope*, look_parent: bool): State{
        return self.get_state(rhs, scope, look_parent, scope.sibling);
    }
    func get_state(self, rhs: Rhs, scope: VarScope*, look_parent: bool, exclude: i32): State{
        return self.get_state(&rhs, scope, look_parent, exclude, true);
    }
    func get_state(self, rhs: Rhs, scope: VarScope*, look_parent: bool, exclude: i32, look_child: bool): State{
        let state = self.get_state(&rhs, scope, look_parent, exclude, look_child);
        rhs.drop();
        return state;
    }
    func get_state(self, rhs: Rhs*, scope: VarScope*, look_parent: bool, exclude: i32, look_child: bool): State{
        //print("get_state {} from {} ch:{} p:{} exc:{}\n", rhs, scope.print_info(), look_child, look_parent, exclude);
        if(rhs is Rhs::VAR){
            let opt = scope.state_map.get_ptr(rhs);
            if(opt.is_some()){
                return State::new(*opt.unwrap(), scope);
            }
        }else if let Rhs::FIELD(scp*, name*) = (rhs){
            let opt = scope.state_map.get_ptr(rhs);
            if(opt.is_some()){
                return State::new(*opt.unwrap(), scope);
            }else{
                return State::new(StateType::NONE, scope);
            }
            //let scp_state = self.get_state(Rhs::new(scp));
        }else{
            let opt = scope.state_map.get_ptr(rhs);
            if(opt.is_some()){
                return State::new(*opt.unwrap(), scope);
            }
        }
        print("{}\n", self.get_scope(self.main_scope).print(self));
        panic("no state {} from {}", rhs, scope.kind);
    }
    func get_state2(self, rhs: Rhs*, scope: VarScope*, look_parent: bool, exclude: i32, look_child: bool): State{
        //print("get_state {} from {} ch:{} p:{} exc:{}\n", rhs, scope.print_info(), look_child, look_parent, exclude);
        
        for(let i = scope.actions.len() - 1;i >= 0;--i){
            let act = scope.actions.get_ptr(i);
            if let Action::MOVE(mv*) = (act){
                //partial move
                if let Expr::Access(scp*, name*)=(mv.rhs.expr){
                    if(rhs is Rhs::VAR){
                        let rhs2 = Rhs::new(scp.get(), self);
                        if(rhs2 is Rhs::VAR && rhs.get_var().id == rhs2.get_var().id){
                            return State::new(StateType::MOVED_PARTIAL, scope);
                        }
                    }
                }
                if(mv.is_lhs(rhs, self)){
                    return State::new(StateType::ASSIGNED, scope);
                }
                if(mv.is_rhs(rhs, self)){
                    return State::new(StateType::MOVED{mv.line}, scope);
                }
            }else if let Action::SCOPE(scp_id, line) = (act){
                if(!look_child){
                    continue;
                }
                if(scp_id == exclude){
                    continue;
                }
                let ch_scope = self.get_scope(scp_id);
                let ch_state = self.get_state(rhs, ch_scope, false, exclude, true);
                if(ch_state.is_moved()){
                    if(!ch_scope.exit.is_jump()){
                        return ch_state;
                    }
                    continue;
                }
                if(ch_scope.kind is ScopeType::ELSE){
                    if(ch_state.is_assigned()){
                        let if_scope = self.get_scope(ch_scope.sibling);
                        let if_state = self.get_state(rhs, if_scope, false, exclude, true);
                        if(if_state.is_assigned()){
                            return ch_state;
                        }
                    }
                }
            }
        }
        if(look_parent && scope.parent != -1){
            let parent = self.get_scope(scope.parent);
            //let res = self.get_state(rhs, parent, true, exclude, false);
            //assert(exclude == -1);
            let res = self.get_state(rhs, parent, true, scope.id, true);
            //todo specificly test if under sibling
            /*if(!(res.kind is StateType::NONE) && scope.kind is ScopeType::ELSE && res.scope.kind is ScopeType::IF && res.scope.id == scope.sibling){
                //ignore sibling move
                return State::new(StateType::NONE, scope);
            }*/
            return res;
        }
        return State::new(StateType::NONE, scope);
    }

    func get_outer_vars(self, scope: VarScope*, list: List<Droppable>*){
        for(let i = 0;i < scope.vars.len();++i){
            let var_id = *scope.vars.get_ptr(i);
            let var = self.get_var(var_id);
            list.add(Droppable::VAR{var});
        }
        for(let i = 0;i < scope.objects.len();++i){
            let obj = scope.objects.get_ptr(i);
            list.add(Droppable::OBJ{obj});
        }
        if(scope.parent != -1){
            let parent = self.get_scope(scope.parent);
            self.get_outer_vars(parent, list);
        }
    }
    func get_outer_vars(self, scope: VarScope*): List<Droppable>{
        let list = List<Droppable>::new();
        self.get_outer_vars(scope, &list);
        return list;
    }
    
    func do_return(self, line: i32){
        let scope = self.get_scope();
        if(verbose){
            print("do_return {} sline: {} line: {}\n", scope.kind, scope.line, line);
        }
        dbg(scope.kind is ScopeType::MAIN && scope.line == 4, 10);
        let drops: List<Droppable> = self.get_outer_vars(scope);
        for(let i = 0;i < drops.len();++i){
            let dr = drops.get_ptr(i);
            if let Droppable::OBJ(obj)=(dr){
                self.drop_obj(obj, scope, line);
            }
            if let Droppable::VAR(var)=(dr){
                self.drop_var(var, scope, true, line);
            }
        }
        if(verbose){
            print("\n");
        }
    }
    func do_return(self, expr: Expr*){
        self.do_move(expr);
        self.do_return(expr.line);
    }

    func do_continue(self){

    }
    func do_break(self){
        
    }

    func end_scope(self, line: i32){
        let scope = self.get_scope();
        //assert(scope.kind is ScopeType::ELSE || scope.kind is ScopeType::IF);
        if(scope.exit.is_jump()){
            //has own drop
            self.set_current(scope.parent);
            return;
        }
        if(verbose){
            print("end_scope {} sline: {} line: {}\n", scope.kind, scope.line, line);
        }
        //drop cur vars & obj & moved outers
        let outers: List<Droppable> = self.get_outer_vars(scope);
        for(let i = 0;i < outers.len();++i){
            let dr: Droppable* = outers.get_ptr(i);
            if let Droppable::OBJ(obj)=(dr){
                if(obj.scope == scope.id){
                    self.drop_obj(obj, scope, line);
                }
            }
            if let Droppable::VAR(var)=(dr){
                dbg(scope.line == 32 && line == 35, 69);
                if(var.scope == scope.id){
                    //local var, we must drop it
                    self.drop_var(var, scope, true, line);
                }else{
                    //outer var, check if moved by sibling
                    if(scope.kind is ScopeType::ELSE){
                        let if_scope = self.get_scope(scope.sibling);
                        let rhs = Rhs::new(var.clone());
                        let state = self.get_state(rhs, if_scope, true);
                        print("sibling {} {}\n", var, state);
                        if(state.is_moved() && !state.scope.exit.is_jump()){
                            self.drop_var(var, scope, false, line);
                        }
                    }
                    else if(scope.kind is ScopeType::IF){
                        let rhs = Rhs::new(var.clone());
                        let parent_scope = self.get_scope(scope.parent);
                        let parent_state = self.get_state(&rhs, parent_scope, true, -1, true);//exc?
                        let if_state = self.get_state(rhs, scope, false);
                        if(parent_state.is_moved()){
                            self.drop_var(var, scope, false, line);
                        }
                    }
                }
            }
        }
        outers.drop();
        self.set_current(scope.parent);
        if(verbose){
            print("\n");
        }
        //update both assign
        if(scope.kind is ScopeType::ELSE){
            for(let i = 0;i < scope.state_map.len();++i){
                let pair: Pair<Rhs, StateType>* = scope.state_map.get_pair_idx(i).unwrap();
                if(pair.b is StateType::ASSIGNED){
                    let if_scope = self.get_scope(scope.sibling);
                    let if_state = if_scope.state_map.get_ptr(&pair.a);
                    if(if_state.is_some() && if_state.unwrap() is StateType::ASSIGNED){
                        let parent = self.get_scope(scope.parent);
                        self.update_state(pair.a, StateType::ASSIGNED, parent);
                    }
                }
            }
        }
    }
    func end_scope_update(self){
        let if_id = self.cur_scope;
        let if_scope = self.get_scope(if_id);
    }
    func end_scope_if(self, else_stmt: Ptr<Stmt>*, line: i32){
        //merge else moves then drop all
        let if_id = self.cur_scope;
        let if_scope = self.get_scope(if_id);
        //self.end_scope_update();
        if(if_scope.exit.is_jump()){
            //has own drop
            self.set_current(if_scope.parent);
            return;
        }
        if(verbose){
            print("end_scope_if line: {}\n", if_scope.line);
            //print("{}\n", self.get_scope(self.main_scope).print(self));
        }

        let visitor = OwnVisitor::new(self);
        let verbose_old = verbose;
        verbose = false;
        //temporarily switch to parent scope, so that else behaves normally
        self.set_current(if_scope.parent);
        let else_id = visitor.begin(else_stmt.get());
        let else_scope = self.get_scope(else_id);
        verbose = verbose_old;
        if_scope = self.get_scope(if_id);//visitor might update state_map, so refresh ptr
        
        let parent_scope = self.get_scope(if_scope.parent);
        let outers = self.get_outer_vars(if_scope);
        if(verbose){
            print("end_scope_if_after line: {}\n", if_scope.line);
        }
        for(let i = 0;i < outers.len();++i){
            let out: Droppable* = outers.get_ptr(i);
            if let Droppable::VAR(var)=(out){
                dbg(var.name.eq("aa"), 44);
                let rhs = Rhs::new(var.clone());
                if(var.scope == if_id){
                    //local var, we must drop it
                    self.drop_var(var, if_scope, false, line);
                    continue;
                }
                let parent_state = self.get_state(&rhs, parent_scope, true, parent_scope.sibling, false);
                print("parent_state={}\n", parent_state);
                if(parent_state.is_moved()){
                    let if_state = self.get_state(&rhs, if_scope, false, -1, true);
                    if(if_state.is_assigned()){
                        let else_state = self.get_state(rhs, else_scope, false);
                        if(else_state.is_none()){
                            //self.drop_var(var, if_scope, false, line);
                            self.drop_var_real(var, line);
                            panic("aha");
                        }
                    }
                    //todo dont look child
                    //already moved in parent, dont check sibling move
                    continue;
                }
                let else_state = self.get_state(rhs, else_scope, true);
                if(else_state.is_moved()){
                    print("sibling2 {}\n", var);
                    //else moved outer, drop in if
                    self.drop_var(var, if_scope, false, line);
                    //panic("moved in sibling {}", var);
                }
            }
        }
        outers.drop();
        //restore old scope
        for(let i = 0;i < parent_scope.actions.len();++i){
            let act = parent_scope.actions.get_ptr(i);
            if let Action::SCOPE(id,sc_line)=(act){
                if(id == else_id){
                    parent_scope.actions.remove(i);
                    break;
                }
            }
        }
        for(let i = 0;i < visitor.scopes.len();++i){
            let st = visitor.scopes.get_ptr(i);
            self.scope_map.remove(st);
        }
        
        if(verbose){
            print("\n");
        }
        self.set_current(if_scope.parent);
    }
    func drop_lhs(self, lhs: Expr*, ptr: Value*){
        if(!self.is_drop_type(lhs)){
            return;
        }
        let lhs2 = Rhs::new(lhs, self);
        let state = self.get_state(lhs2, self.get_scope(), true);
        if(state.is_moved()){
            return;
        }
        if(verbose){
            print("drop_lhs {} line: {}\n", lhs, lhs.line);
        }
        let rt = self.get_type(lhs);
        self.drop_real(&rt, ptr, lhs.line);
        rt.drop();
    }
}

//drop logic
impl Own{
    func drop_partial(self, var: Variable*, scope: VarScope*){
        //check if all fields moved
        //let rhs = Rhs::new(var);
        let rt = self.compiler.get_resolver().visit_type(&var.type);
        let decl = self.compiler.get_resolver().get_decl(&rt).unwrap();
        let fields = decl.get_fields();
        let moved_fields = List<String>::new();
        for(let i = scope.actions.len() - 1;i >= 0;--i){
            let act = scope.actions.get_ptr(i);
            if let Action::MOVE(mv)=(act){
                if let Expr::Access(scp*, name*)=(mv.rhs.expr){
                    let rhs2 = Rhs::new(scp.get(), self);
                    if(rhs2 is Rhs::VAR && var.id == rhs2.get_var().id){
                        moved_fields.add(name.clone());
                        //return State::new(StateType::MOVED_PARTIAL, scope);
                    }
                    
                }
            }
        }
        for(let i = 0;i < fields.len();++i){
            let fd = fields.get_ptr(i);
            if(!self.is_drop_type(&fd.type)){
                continue;
            }
            if(!moved_fields.contains(&fd.name)){
                self.compiler.get_resolver().err(var.line, format("field {} not moved", fd.name));
            }
        }
        rt.drop();
    }
    func drop_var(self, var: Variable*, scope: VarScope*, look_parent: bool, line: i32){
        if(var.is_self && is_drop_method(self.method)){
            return;
        }
        if(var.type.is_pointer()){
            //use get_state for each field
            //self.drop_partial(var, scope);
            return;
        }
        let rhs = Rhs::new(var.clone());
        dbg(var.name.eq("f"), 33);
        let state = self.get_state(rhs, scope, look_parent);
        if(print_drop){
            print("drop_var {} state: {}\n", var, state);
        }
        if(var.name.eq("f") && var.line == 18){
            print("{}\n", self.get_scope(self.main_scope).print(self));
        }
        if(state.kind is StateType::MOVED_PARTIAL){
            self.drop_partial(var, scope);
            //self.compiler.get_resolver().err(var.line, format("var {} moved partially", var));
            return;
        }
        if(state.is_moved()){
            return;
        }
        let rt = self.compiler.get_resolver().visit_type(&var.type);
        self.drop_real(&rt, var.ptr, line);
        rt.drop();
    }
    func drop_var_real(self, var: Variable*, line: i32){
        if(print_drop){
            print("drop_var {}\n", var);
        }
        let rt = self.compiler.get_resolver().visit_type(&var.type);
        self.drop_real(&rt, var.ptr, line);
        rt.drop();
    }
    func drop_obj(self, obj: Object*, scope: VarScope*, line: i32){
        let rhs = Rhs::new(obj.expr, self);
        let state = self.get_state(rhs, scope, true);
        if(print_drop){
            print("drop_obj {} state: {} line: {}\n", obj.expr, state.kind, line);
        }
        if(state.is_moved()){
            return;
        }
        let resolver = self.compiler.get_resolver();
        let rt = resolver.visit(obj.expr);
        self.drop_real(&rt, obj.ptr, line);
        rt.drop();
    }
    func drop_obj_real(self, obj: Object*){
        let resolver = self.compiler.get_resolver();
        let rt = resolver.visit(obj.expr);
        self.drop_real(&rt, obj.ptr, obj.expr.line);
        rt.drop();
    }

    func drop_real(self, rt: RType*, ptr: Value*, line: i32){
        if(!self.is_drop_type(&rt.type)){
            return;
        }
        let proto = self.get_proto(rt);
        let args = make_args();
        args_push(args, ptr);
        CreateCall(proto, args);
        dbg(rt.type.eq("List<u8>"), 10);
        dbg(line == 318, 33);
        print("drop_real {} line: {}\n", rt.type, line);
    }
    func get_proto(self, rt: RType*): Function*{
        let resolver = self.compiler.get_resolver();
        let decl = resolver.get_decl(rt).unwrap();
        let helper = DropHelper{resolver};
        let method = helper.get_drop_method(rt);
        if(method.is_generic){
            panic("generic {}", rt.type);
        }
        let protos = self.compiler.protos.get();
        let mangled = mangle(method);
        if(!protos.funcMap.contains(&mangled)){
            self.compiler.make_proto(method);
        }
        let proto = protos.get_func(method);
        mangled.drop();
        return proto;
    }
}


impl VarScope{
    func print(self, own: Own*): String{
        let f = Fmt::new();
        self.debug(&f, own, "");
        return f.unwrap();
    }
    func print_info(self): String{
        let f = Fmt::new();
        f.print("VarScope{");
        f.print(&self.kind);
        f.print(", line: ");
        f.print(&self.line);
        f.print("}");
        return f.unwrap();
    }
    func debug(self, f: Fmt*, own: Own*, indent: str){
        f.print(indent);
        f.print("VarScope ");
        f.print(&self.kind);
        f.print(", line: ");
        f.print(&self.line);
        f.print("{");
        for(let i = 0;i < self.vars.len();++i){
            let var_id = *self.vars.get_ptr(i);
            let var = own.get_var(var_id);
            f.print("\n");
            f.print(indent);
            f.print("  let ");
            f.print(&var.name);
            f.print(": ");
            f.print(&var.type);
            f.print(", line: ");
            f.print(&var.line);
        }
        for(let i=0;i<self.objects.len();++i){
            let obj = self.objects.get_ptr(i);
            f.print("\n");
            f.print(indent);
            f.print("  obj line: ");
            f.print(&obj.expr.line);
            f.print(", ");
            f.print(obj.expr);
        }
        for(let i=0;i<self.actions.len();++i){
            let act = self.actions.get_ptr(i);
            if let Action::SCOPE(id, line)=(act){
                let ch_scope = own.get_scope(id);
                let id2 = format("{}  ", indent);
                f.print("\n");
                ch_scope.debug(f, own, id2.str());
                id2.drop();
            }else{
                f.print("\n");
                f.print(indent);
                f.print("  ");
                f.print(act);
            }
        }
        for(let i=0;i<self.state_map.len();++i){
            let pair = self.state_map.get_pair_idx(i).unwrap();
            f.print("\n");
            f.print(indent);
            f.print("  state(");
            pair.a.debug(f);
            f.print(")");
            f.print("=");
            pair.b.debug(f);
        }
        f.print("\n");
        f.print(indent);
        f.print("}");
    }
}

impl Debug for Action{
    func debug(self, f: Fmt*){
        f.print("Action::");
        if let Action::MOVE(mv*)=(self){
            f.print("MOVE{");
            f.print(mv);
            f.print(" line: ");
            f.print(&mv.line);
            f.print("}");
        }
        if let Action::SCOPE(id, line)=(self){
            f.print("SCOPE{");
            f.print(&id);
            f.print(", ");
            f.print(&line);
            f.print("}");
        }
    }
}

impl Debug for Move{
    func debug(self, f: Fmt*){
        f.print("Move{");
        if(self.lhs.is_some()){
            f.print(self.lhs.get());
            f.print(" = ");
        }
        Debug::debug(&self.rhs, f);
        f.print("}");
    }
}

impl Debug for Variable{
    func debug(self, f: Fmt*){
        f.print("Variable{");
        f.print(&self.name);
        f.print(": ");
        f.print(&self.type);
        f.print(", line: ");
        f.print(&self.line);
        f.print("}");
    }
}
impl Debug for Rhs{
    func debug(self, f: Fmt*){
        if let Rhs::EXPR(e)=(self){
            f.print("Rhs::EXPR{");
            f.print(e);
            f.print("}");
        }
        else if let Rhs::VAR(v*)=(self){
            f.print("Rhs::VAR{");
            f.print(v);
            f.print("}");
        }
        else if let Rhs::FIELD(scp*,name*)=(self){
            f.print("Rhs::FIELD{");
            f.print(scp);
            f.print(", ");
            f.print(name);
            f.print("}");
        }
    }
}
impl Clone for Rhs{
    func clone(self): Rhs{
        if let Rhs::EXPR(e)=(self){
            return Rhs::EXPR{e};
        }
        if let Rhs::VAR(v*)=(self){
            return Rhs::VAR{v.clone()};
        }
        panic("{}", self);
    }
}
impl Eq for Rhs{
    func eq(self, other: Rhs*): bool{
        let s1 = Fmt::str(self);
        let s2 = Fmt::str(other);
        let res = s1.eq(&s2);
        s1.drop();
        s2.drop();
        return res;
    }
}

impl Debug for Moved{
    func debug(self, f: Fmt*){
        if(self.var.is_some()){
            //f.print("var{");
            self.var.get().debug(f);
            //f.print("}");
        }else{
            f.print(self.expr);
        }
    }
}