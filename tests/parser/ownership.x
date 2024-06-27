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

func is_drop_method(method: Method*): bool{
    if(method.name.eq("drop") && method.parent.is_impl()){
        let imp =  method.parent.as_impl();
        return imp.trait_name.is_some() && imp.trait_name.get().eq("Drop");
    }
    return false;
}

//prm or var
//#derive(Debug)
struct Variable {
    name: String;
    type: Type;
    ptr: Value*;
    id: i32;
    line: i32;
    scope: i32;
    is_self: bool;
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
    vars: List<Variable>;
    objects: List<Object>;
    actions: List<Action>;
    exit: Exit;
    parent: i32;
    sibling: i32;
    state_map: Map<i32, StateType>; //var_id -> StateType
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
impl State{
    func new(kind: StateType, scope: VarScope*): State{
        return State{kind, scope};
    }
    func is_moved(self): bool{
        return self.kind is StateType::MOVED || self.kind is StateType::MOVED_PARTIAL;
    }
}

#derive(Debug)
enum Rhs{
    EXPR(e: Expr*),
    VAR(v: Variable*)
}
impl Rhs{
    func get_var(self): Variable*{
        if let Rhs::VAR(v)=(self){
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
        panic("");
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
    func eq(self, expr: Expr*, resolver: Resolver*): bool{
        if let Rhs::EXPR(e)=(self){
            if(e.id == expr.id){
                return true;
            }
            let rt1 = resolver.visit(e);
            let rt2 = resolver.visit(expr);
            //return self.is_vh(vh, compiler);
            if(rt1.vh.is_some() && rt2.vh.is_some()){
                return rt1.vh.get().id == rt2.vh.get().id;
            }
            return false;
        }
        let rt2 = resolver.visit(expr);
        if(rt2.vh.is_some()){
            return self.get_var().id == rt2.vh.get().id;
        }
        return false;
    }
}

struct Move{
    lhs: Option<Expr*>;
    rhs: Expr*;
    line: i32;
}
impl Move{
    func is_lhs(self, lhs2: Rhs*, own: Own*): bool{
        if(self.lhs.is_none()){
            return false;
        }
        let lhs: Expr* = *self.lhs.get();
        return lhs2.eq(lhs, own.compiler.get_resolver());
    }
}

impl VarScope{
    func new(kind: ScopeType, line: i32, exit: Exit): VarScope{
        let scope = VarScope{
            kind: kind,
            id: ++last_scope,
            line: line,
            vars: List<Variable>::new(),
            objects: List<Object>::new(),
            actions: List<Action>::new(),
            exit: exit,
            parent: -1,
            sibling: -1,
            state_map: Map<i32, StateType>::new()
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
            scope_map: Map<i32, VarScope>::new()
        };
        res.scope_map.add(main_scope.id, main_scope);
        return res;
    }
    func add_scope(self, kind: ScopeType, line: i32, exit: Exit): i32{
        let scope = VarScope::new(kind, line, exit);
        scope.parent = self.get_scope().id;
        let id = scope.id;
        self.scope_map.add(scope.id, scope);
        self.get_scope().actions.add(Action::SCOPE{id, line});        
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
    //register var & obj
    func is_drop_type(self, type: Type*): bool{
        let helper = DropHelper{self.compiler.get_resolver()};
        return helper.is_drop_type(type);
    }
    func add_prm(self, p: Param*, ptr: Value*){
        if(!self.is_drop_type(&p.type)) return;
        let var = Variable{
            name: p.name.clone(),
            type: p.type.clone(),
            ptr: ptr,
            id: p.id,
            line: p.line,
            scope: self.get_scope().id,
            is_self: p.is_self
        };
        self.get_scope().vars.add(var);
    }
    func add_var(self, f: Fragment*, ptr: Value*){
        let rt = self.compiler.get_resolver().visit(f);
        if(!self.is_drop_type(&rt.type)){
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
        self.get_scope().vars.add(var);
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
        self.get_scope().vars.add(var);
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
        //panic("add_obj {}: {} in {}", expr, type, printMethod(self.method));
    }

    func do_move(self, expr: Expr*){
        let rt = self.compiler.get_resolver().visit(expr);
        if(!self.is_drop_type(&rt.type)){
            rt.drop();
            return;
        }
        let mv = Move{
            lhs: Option<Expr*>::new(),
            rhs: expr,
            line: expr.line
        };
        let act = Action::MOVE{mv};
        if(verbose){
            //print("move {} line:{}\n", mv.rhs, mv.line);
            print("do_move {}\n", act);
        }
        self.get_scope().actions.add(act);
        if(rt.vh.is_some()){
            self.get_scope().state_map.add(rt.vh.get().id, StateType::MOVED);
        }else{
            self.get_scope().state_map.add(expr.id, StateType::MOVED);
        }
        rt.drop();
    }

    func get_state(self, rhs: Rhs, scope: VarScope*, look_parent: bool): State{
        return self.get_state(rhs, scope, look_parent, scope.sibling);
    }
    func get_state(self, rhs: Rhs, scope: VarScope*, look_parent: bool, exclude: i32): State{
        return self.get_state(rhs, scope, look_parent, exclude, true);
    }
    func get_state(self, rhs: Rhs, scope: VarScope*){
        let list = List<VarScope*>::new();
        list.add(scope);

    }
    func get_state(self, rhs: Rhs, scope: VarScope*, look_parent: bool, exclude: i32, look_child: bool): State{
        for(let i = scope.actions.len() - 1;i >= 0;--i){
            let act = scope.actions.get_ptr(i);
            if let Action::MOVE(mv*) = (act){
                if(rhs is Rhs::EXPR){
                    //tmp obj moved immediatly
                    if(mv.rhs.id == rhs.get_id()){
                        return State::new(StateType::MOVED{mv.line}, scope);
                    }
                }
                let mv_rt = self.compiler.get_resolver().visit(mv.rhs);
                if(mv_rt.vh.is_some()){
                    if(rhs.is_vh(mv_rt.vh.get(), self.compiler.get_resolver())){
                        mv_rt.drop();
                        return State::new(StateType::MOVED{mv.line}, scope);
                    }
                }else{
                    mv_rt.drop();
                    if(mv.rhs.id == rhs.get_id()){
                        return State::new(StateType::MOVED{mv.line}, scope);
                    }
                }
                if(mv.is_lhs(&rhs, self)){
                    return State::new(StateType::ASSIGNED, scope);
                }
            }else if let Action::SCOPE(scp_id, line) = (act){
                if(!look_child){
                    continue;
                }
                if(scp_id == exclude){
                    continue;
                }
                let scp = self.get_scope(scp_id);
                let ch_state = self.get_state(rhs, scp, false, exclude);
                if(!(ch_state.kind is StateType::NONE)){
                    if(!scp.exit.is_jump()){
                        //check then scope too
                        if(scp.kind is ScopeType::ELSE && ch_state.kind is ASSIGNED){
                            //todo remove assign, todo dominate
                        }
                        return ch_state;
                    }
                }
            }
        }
        if(look_parent && scope.parent != -1){
            let parent = self.get_scope(scope.parent);
            let res = self.get_state(rhs, parent, true, exclude, false);
            //todo specificly test if under sibling
            /*if(!(res.kind is StateType::NONE) && scope.kind is ScopeType::ELSE && res.scope.kind is ScopeType::IF && res.scope.id == scope.sibling){
                //ignore sibling move
                return State::new(StateType::NONE, scope);
            }*/
            return res;
        }
        return State::new(StateType::NONE, scope);
    }
    func check(self, expr: Expr*){
        let scope = self.get_scope();
        let rhs = Rhs::EXPR{expr};
        dbg(expr.line == 266, 100);
        let state = self.get_state(rhs, scope, true);
        //print("check {} line:{} {}\n", expr, expr.line, state_pair.a);
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

    func get_outer_vars(self, scope: VarScope*, list: List<Droppable>*){
        for(let i = 0;i < scope.vars.len();++i){
            let var = scope.vars.get_ptr(i);
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
            print("do_return {} line: {}\n", scope.kind, line);
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
        if(verbose){
            print("do_return {}\n", expr.line);
        }
        self.do_return(expr.line);
    }

    func do_continue(self){

    }
    func do_break(self){
        
    }

    func end_scope(self, line: i32){
        let scope = self.get_scope();
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
                if(var.scope == scope.id){
                    //local var, we must drop it
                    self.drop_var(var, scope, true, line);
                }else{
                    //outer var, check if moved by sibling
                    if(scope.kind is ScopeType::ELSE){
                        let if_scope = self.get_scope(scope.sibling);
                        let rhs = Rhs::VAR{var};
                        let state = self.get_state(rhs, if_scope, false);
                        if(state.is_moved() && !state.scope.exit.is_jump()){
                            print("sibling {} {}\n", var, state);
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
    }
    func end_scope_if(self, else_stmt: Stmt*, line: i32){
        //merge else moves then drop all
        let if_id = self.cur_scope;
        let if_scope = self.get_scope(if_id);
        //temporarily switch to parent scope, so that else behaves normally
        self.set_current(if_scope.parent);
        let visitor = OwnVisitor::new(self);
        let else_id = visitor.begin(else_stmt);
        if(verbose){
            print("end_scope_if line: {}\n", if_scope.line);
            print("{}\n", self.get_scope(self.main_scope).print(self));
        }
        let else_scope = self.get_scope(else_id);
        let parent_scope = self.get_scope(if_scope.parent);
        let outers = self.get_outer_vars(if_scope);
        for(let i = 0;i < outers.len();++i){
            let out: Droppable* = outers.get_ptr(i);
            if let Droppable::VAR(var)=(out){
                let rhs = Rhs::VAR{var};
                if(var.scope == if_id){
                    //local var, we must drop it
                    self.drop_var(var, if_scope, false, line);
                    continue;
                }
                if(self.get_state(rhs, parent_scope, true, parent_scope.sibling, false).is_moved()){
                    //todo dont look child
                    //already moved in parent, dont check sibling move
                    continue;
                }
                let state = self.get_state(rhs, else_scope, true);
                if(state.is_moved()){
                    print("sibling2 {}\n", var);
                    //else moved outer, drop in if
                    let rt = self.compiler.get_resolver().visit_type(&var.type);
                    //self.drop_real(&rt, var.ptr, var.line);
                    self.drop_var(var, if_scope, false, line);
                    rt.drop();
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
    }

    //move rhs
    func do_assign(self, lhs: Expr*, rhs: Expr*){
        let scope = self.get_scope();
        let rt = self.compiler.get_resolver().visit(rhs);
        if(!self.is_drop_type(&rt.type)){
            rt.drop();
            return;
        }
        scope.actions.add(Action::MOVE{Move{Option::new(lhs), rhs, lhs.line}});
    }
    func drop_lhs(self, lhs: Expr*, ptr: Value*){
        let rhs = Rhs::EXPR{lhs};
        let state = self.get_state(rhs, self.get_scope(), true);
        if(state.is_moved()){
            return;
        }
        if(verbose){
            print("drop_lhs {} line: {}\n", lhs, lhs.line);
        }
        let rt = self.compiler.get_resolver().visit(lhs);
        self.drop_real(&rt, ptr, lhs.line);
        rt.drop();
    }
}

//drop logic
impl Own{
    func drop_var(self, var: Variable*, scope: VarScope*, look_parent: bool, line: i32){
        if(var.is_self && is_drop_method(self.method)){
            return;
        }
        let rhs = Rhs::VAR{var};
        let state = self.get_state(rhs, scope, look_parent);
        if(print_drop){
            print("drop_var {} state: {}\n", var, state);
        }
        if(state.is_moved()){
            return;
        }
        let rt = self.compiler.get_resolver().visit_type(&var.type);
        self.drop_real(&rt, var.ptr, line);
        rt.drop();
    }
    func drop_obj(self, obj: Object*, scope: VarScope*, line: i32){
        let rhs = Rhs::EXPR{obj.expr};
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
    func debug(self, f: Fmt*, own: Own*, indent: str){
        f.print(indent);
        f.print("VarScope ");
        f.print(&self.kind);
        f.print(", line: ");
        f.print(&self.line);
        f.print("{");
        for(let i=0;i<self.vars.len();++i){
            let var = self.vars.get_ptr(i);
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
            f.print(*self.lhs.get());
            f.print(" = ");
        }
        f.print(self.rhs);
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