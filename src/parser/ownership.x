import std/map
import std/hashmap
import std/stack
import std/io

import ast/ast
import ast/utils
import ast/printer

import parser/own_visitor
import parser/own_helper
import parser/own_model
import parser/compiler
import parser/resolver
import parser/compiler_helper
import parser/method_resolver
import parser/debug_helper
import parser/derive
import parser/drop_helper
import parser/exit

//todo endscope incorrectly warns 'field not moved at...' but that scope is irrevelant with var.field

func hasenv(key: str): bool{
    return std::getenv(key).is_some();
}

static last_scope: i32 = 0;
static verbose: bool = hasenv("own_verbose");
static print_check: bool = hasenv("print_check");

#derive(Debug)
enum PrintKind{
    None,
    Valid,
    Any,
}

static print_kind: PrintKind = init_print();
static print_drop_real: bool = hasenv("print_drop_real");
static print_drop_lhs: bool = hasenv("print_drop_lhs");

static drop_enabled: bool = hasenv("drop_enabled");
static drop_lhs_enabled: bool =  hasenv("drop_lhs_enabled");
static move_ptr_field = true;
static allow_else_move = true;

static logger = Logger::new();

func init_print(): PrintKind{
    let opt = std::getenv("own_print");
    if(opt.is_none()) return PrintKind::None;
    if(opt.get().eq("any")) return PrintKind::Any;
    if(opt.get().eq("valid")) return PrintKind::Valid;
    panic("Invalid value for own_print: {}", opt.get());
}

struct Logger{
    list: List<String>;
}
impl Logger{
    func new(): Logger{
        return Logger{list: List<String>::new()};
    }
    func add(msg: String){
        logger.list.add(msg);
    }
    func exit(own: Own*){
        if(logger.list.empty()){
            return;
        }
        let mstr = printMethod(own.method);
        print("in {}\n{}\n", &own.method.path, &mstr);
        for msg in &logger.list{
            print("  {}", msg);
        }
        print("\n");
        logger.list.clear();
        mstr.drop();
    }
}

struct Own{
    compiler: Compiler*;
    method: Method*;
    main_scope: i32;
    cur_scope: i32;
    scope_map: Map<i32, VarScope>;
    var_map: Map<i32, Variable>;
}

impl Drop for Own{
    func drop(*self){
        self.scope_map.drop();
        self.var_map.drop();
        Logger::exit(&self);
    }
}

impl Own{
    func new(c: Compiler*, m: Method*): Own{
        //print("print_kind={:?}\n", print_kind);
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
    func get_resolver(self): Resolver*{
        return self.compiler.get_resolver();
    }
    func add_scope(self, kind: ScopeType, line: i32, exit: Exit, is_empty: bool): i32{
        if(verbose){
            print("add_scope {:?} line:{}\n", kind, line);
        }
        let scope = VarScope::new(kind, line, exit);
        scope.is_empty = is_empty;
        let parent = self.get_scope();
        //copy parent states
        for pair in &parent.state_map{
            scope.state_map.add(pair.a.clone(), pair.b.clone());
        }
        scope.parent = parent.id;
        let id = scope.id;      
        self.scope_map.add(scope.id, scope);
        self.set_current(id);
        return id;
    }
    func add_scope(self, kind: ScopeType, stmt: Body*): i32{
        let exit = Exit::get_exit_type(stmt);
        return self.add_scope(kind, stmt.line(), exit, false);
    }
    func add_scope(self, kind: ScopeType, stmt: Stmt*): i32{
        let exit = Exit::get_exit_type(stmt);
        return self.add_scope(kind, stmt.line, exit, false);
    }
    func add_scope(self, kind: ScopeType, stmt: Block*): i32{
        let exit = Exit::get_exit_type(stmt);
        return self.add_scope(kind, stmt.line, exit, false);
    }
    func add_scope(self, kind: ScopeType, rhs: MatchRhs*): i32{
        let exit = Exit::get_exit_type(rhs);
        return self.add_scope(kind, 1/*todo*/, exit, false);
    }
    func set_current(self, id: i32){
        assert(id != -1);
        self.cur_scope = id;
    }
    func get_scope(self): VarScope*{
        return self.scope_map.get(&self.cur_scope).unwrap();
    }
    func get_scope(self, id: i32): VarScope*{
        return self.scope_map.get(&id).unwrap();
    }
    func get_var(self, id: i32): Variable*{
        let opt = self.var_map.get(&id);
        if(opt.is_none()){
            panic("var not found id={} scope={:?}", id, self.get_scope(self.main_scope).print(self));
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
    func add_prm(self, p: Param*, ptr: LLVMOpaqueValue*){
        //print("add_prm {}:{} line={}\n", p.name, p.type, p.line);
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
    func add_var(self, f: Fragment*, ptr: LLVMOpaqueValue*){
        let rt = self.compiler.get_resolver().visit_frag(f);
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
    func add_iflet_var(self, arg: ArgBind*, fd: FieldDecl*, ptr: LLVMOpaqueValue*){
        if(!self.is_drop_type(&fd.type)) return;
        /*if(rhs_ty.is_pointer()){
            self.get_resolver().err(arg.line, format("can't deref member from ptr '{}'", arg.name));
        }*/
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
    func add_obj(self, expr: Expr*, ptr: LLVMOpaqueValue*, type: Type*){
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

    // func do_move(self, block: Block*){
    // }

    func do_move(self, expr: Expr*){
        let rt = self.get_type(expr);
        if(!self.is_drop_type(&rt.type)){
            rt.drop();
            return;
        }
        if(verbose){
            let mv = Move{
                lhs: Option<Moved>::new(),
                rhs: Moved::new(expr, self),
                line: expr.line
            };
            print("do_move {:?}\n", &mv);
            mv.drop();
        }
        let rhs = Rhs::new(expr, self);
        if let Rhs::FIELD(scp, name)=&rhs{
            if(!move_ptr_field && scp.type.is_pointer()){
                self.get_resolver().err(expr, "move out of pointer");
            }
        }
        let scope = self.get_scope();
        self.update_state(rhs, StateType::MOVED{expr.line}, scope);
        match expr{
            Expr::Par(bx) => {
                self.do_move(bx.get());
            },
            _ => {}
        }
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
        if(verbose){
            let mv = Move{Option::new(Moved::new(lhs, self)), Moved::new(rhs, self), lhs.line};
            print("do_move {:?} line:{}\n", &mv, lhs.line);
            mv.drop();
        }
        self.update_state(rhs, &rt, StateType::MOVED{rhs.line}, scope);
        let rt_lhs = self.get_type(lhs);
        self.update_state(lhs, &rt_lhs, StateType::ASSIGNED, scope);
        rt.drop();
        rt_lhs.drop();
    }

    func update_state(self, expr: Expr*, rt: RType*, kind: StateType, scope: VarScope*){
        let rhs = Rhs::new(expr, self);
        self.update_state(rhs, kind, scope);
    }
    func update_state(self, rhs: Rhs, kind: StateType, scope: VarScope*){
        //set parent partially moved
        /*if let Rhs::FIELD(scp*, name*) = &rhs{
            let scp_rhs = Rhs::new(scp.clone());
            self.update_state(scp_rhs, StateType::MOVED_PARTIAL, scope);
        }*/
        //todo remove self param
        scope.state_map.add(rhs, kind);
    }
    func end_scope_update(self){
        let id = self.cur_scope;
        let scope = self.get_scope(id);
        let parent = self.get_scope(scope.parent);
        if(scope.kind is ScopeType::WHILE || scope.kind is ScopeType::FOR){
            //copy states to parent directly
            for pair in &scope.state_map{
                self.update_state(pair.a.clone(), pair.b.clone(), parent);
            }
            return;
        }
        if(scope.kind is ScopeType::IF){
            //move only in if
            /*for(let i = 0;i < scope.state_map.len();++i){
                let pair: Pair<Rhs, StateType>* = scope.state_map.get_pair_idx(i).unwrap();
                if(pair.b is StateType::MOVED || pair.b is StateType::MOVED_PARTIAL){
                    parent.state_map.add(pair.a.clone(), pair.b);
                }
            }*/
            return;
        }
        if(scope.kind is ScopeType::MATCH_CASE){
            //todo
            return;
        }
        if(!(scope.kind is ScopeType::ELSE)){
            panic("end {:?}", scope.kind);
        }
        //move in else -> parent
        if(!scope.exit.is_jump()){
            for pair in &scope.state_map{//Pair<Rhs, StateType>*
                if(pair.b is StateType::MOVED || pair.b is StateType::MOVED_PARTIAL){
                    self.update_state(pair.a.clone(), pair.b.clone(), parent);
                }
            }
        }
        //move in if -> parent
        let if_scope = self.get_scope(scope.sibling);
        if(!if_scope.exit.is_jump()){
            for pair in &if_scope.state_map{
                if(pair.b is StateType::MOVED || pair.b is StateType::MOVED_PARTIAL){
                    self.update_state(pair.a.clone(), pair.b.clone(), parent);
                }
            }
        }
        //both assign -> parent
        for pair in &scope.state_map{//Pair<Rhs, StateType>*
            if(pair.b is StateType::ASSIGNED){
                let if_state = if_scope.state_map.get(pair.a);
                if(if_state.is_some() && if_state.unwrap() is StateType::ASSIGNED){
                    self.update_state(pair.a.clone(), StateType::ASSIGNED, parent);
                }
            }
        }
        
    }

    func check(self, expr: Expr*){
        let rt = self.get_type(expr);
        if(!self.is_drop_type(&rt.type)){
            rt.drop();
            return;
        }
        rt.drop();
        let scope = self.get_scope();
        if(print_check){
            print("check {:?} line:{}\n", expr, expr.line);
        }
        let rhs = Rhs::new(expr, self);
        let state = self.get_state(&rhs, scope);
        rhs.drop();
        if let StateType::MOVED(line)=state.kind{
            // let scope_str = self.get_scope(self.main_scope).print(self);
            // print("{}\n", scope_str);
            // scope_str.drop();
            let tmp = printMethod(self.method);
            self.compiler.get_resolver().err(expr, format("use after move in {}:{} {:?}", tmp, line, expr));
            tmp.drop();
        }
    }
    func check_field(self, expr: Expr*){
        if let Expr::Access(scp, name)=expr{
            //scope could be partially moved, check right field is valid
        }else{
            panic("check_field not field access {:?}", expr);
        }
    }

    func get_state(self, rhs: Rhs*, scope: VarScope*): State{
        //print("get_state {} from {}\n", rhs, scope.print_info());
        let opt = scope.state_map.get(rhs);
        if(opt.is_none()){
            if(rhs is Rhs::FIELD){
                return State::new(StateType::NONE, scope);
            }
            print("{:?}\n", self.get_scope(self.main_scope).print(self));
            panic("no state {:?} from {:?}", rhs, scope.kind);
        }
        let state: StateType = *opt.unwrap();
        if let Rhs::FIELD(scp, name) = rhs{
            return State::new(state, scope);
            //let scp_state = self.get_state(Rhs::new(scp));
        }
        if(rhs is Rhs::EXPR){
            return State::new(state, scope);
        }
        //main var is valid but field moved -> partial
        if(state is StateType::NONE || state is StateType::ASSIGNED){
            for pair in &scope.state_map{
                if(!(pair.b is StateType::MOVED)){
                    continue;
                }
                if let Rhs::FIELD(scp, name) = pair.a{
                    if(scp.id == rhs.get_id()){
                        return State::new(StateType::MOVED_PARTIAL, scope);
                    }
                }
            }
        }
        return State::new(state, scope);
    }

    func get_outer_vars(self, scope: VarScope*, until_loop: bool, list: List<Droppable>*){
        for var_id in &scope.vars{
            let var = self.get_var(*var_id);
            list.add(Droppable::VAR{var});
        }
        for obj in &scope.objects{
            list.add(Droppable::OBJ{obj});
        }
        if(until_loop && (scope.kind is ScopeType::WHILE || scope.kind is ScopeType::FOR)){
            return;
        }
        if(scope.parent != -1){
            let parent = self.get_scope(scope.parent);
            self.get_outer_vars(parent, until_loop,  list);
        }
    }
    func get_outer_vars(self, scope: VarScope*): List<Droppable>{
        let list = List<Droppable>::new();
        self.get_outer_vars(scope, false, &list);
        return list;
    }
    func get_outer_vars_loop(self, scope: VarScope*): List<Droppable>{
        let list = List<Droppable>::new();
        self.get_outer_vars(scope, true, &list);
        return list;
    }
    
    func do_return(self, line: i32){
        let scope = self.get_scope();
        if(verbose){
            print("do_return {:?} sline: {} line: {}\n", scope.kind, scope.line, line);
        }
        self.check_ptr_field(scope, line);
        let drops: List<Droppable> = self.get_outer_vars(scope);
        for dr in &drops{
            self.drop_any(dr, scope, line);
        }
        drops.drop();
        if(verbose){
            print("\n");
        }
    }
    func do_return(self, expr: Expr*){
        self.do_move(expr);
        self.do_return(expr.line);
    }

    func drop_any(self, dr: Droppable*, scope: VarScope*, line: i32){
        match dr{
            Droppable::OBJ(obj) => {
                self.drop_obj(*obj, scope, line);
            },
            Droppable::VAR(var) => {
                self.drop_var(*var, scope, line);
            }
        }
    }

    func do_continue(self, line: i32){
        //drop vars & objs until the loop
        let scope = self.get_scope();
        let drops = self.get_outer_vars_loop(scope);
        for dr in &drops{
            self.drop_any(dr, scope, line);
        }
        drops.drop();
    }
    
    func do_break(self, line: i32){
        self.do_continue(line);
    }

    func check_ptr_field(self, scope: VarScope*, line: i32){
        if(!move_ptr_field) return;
        for pair in &scope.state_map{
            if let StateType::MOVED(mv_line) = pair.b{
                if let Rhs::FIELD(scp, name) = pair.a{
                    if(scp.type.is_pointer()){
                        self.get_resolver().err(line, format("move out of ptr but not assigned\nmoved in: {}, {:?}", mv_line, pair.a));
                    }
                }
            }
        }
    }

    func end_scope(self, line: i32){
        let scope = self.get_scope();
        //assert(scope.kind is ScopeType::ELSE || scope.kind is ScopeType::IF);
        if(scope.exit.is_jump()){
            //has own drop, just update state
            self.end_scope_update();
            self.set_current(scope.parent);
            return;
        }
        if(verbose){
            print("end_scope {:?} sline: {} line: {}\n", scope.kind, scope.line, line);
        }
        //drop cur vars & obj & moved outers
        let outers: List<Droppable> = self.get_outer_vars(scope);
        for dr in &outers{
            if let Droppable::OBJ(obj)=dr{
                //local obj, drop it
                if((*obj).scope == scope.id){
                    self.drop_obj(*obj, scope, line);
                }
                continue;
            }
            let var = dr.as_var();
            if(var.scope == scope.id){
                //local var, drop it
                self.drop_var(var, scope, line);
                continue;
            }
            //outer var, check if moved by sibling
            if(scope.kind is ScopeType::ELSE){
                let if_scope = self.get_scope(scope.sibling);
                let rhs = Rhs::new(var.clone());
                let if_state = self.get_state(&rhs, if_scope);
                if(if_state.is_moved() && !if_state.scope.exit.is_jump()){
                    self.drop_var(var, scope, line);
                }
                rhs.drop();
            }
            else if(scope.kind is ScopeType::IF){
                //if without else
                let rhs = Rhs::new(var.clone());
                let parent_scope = self.get_scope(scope.parent);
                let parent_state = self.get_state(&rhs, parent_scope);
                let if_state = self.get_state(&rhs, scope);
                //parent moved, if reinit, else inferred moved, so must drop
                if(parent_state.is_moved()){
                    self.drop_var(var, scope, line);
                }
                rhs.drop();
            }
            //forbid else-only move
            if(!allow_else_move && scope.kind is ScopeType::ELSE && !scope.is_empty){
                let rhs = Rhs::new(var.clone());
                let st = self.get_state(&rhs, scope);
                if(st.is_moved()){
                    let if_scope = self.get_scope(scope.sibling);
                    let if_state = self.get_state(&rhs, if_scope);
                    if(!if_state.is_moved()){
                        self.get_resolver().err(scope.line, format("else-only move of {:?} in {}\n", var, st.get_line()));
                    }
                }
                rhs.drop();
            }
        }
        outers.drop();
        self.end_scope_update();
        self.set_current(scope.parent);
        if(verbose){
            print("\n");
        }
    }

    func end_scope_if(self, else_stmt: Ptr<Body>*, line: i32){
        //merge else moves then drop all
        let if_id = self.cur_scope;
        let if_scope = self.get_scope(if_id);
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
        for out in &outers{
            if let Droppable::OBJ(obj) = out{
                //local obj, drop it
                if((*obj).scope == if_scope.id){
                    self.drop_obj(*obj, if_scope, line);
                }
                continue;
            }
            let var = out.as_var();
            if(var.scope == if_id){
                //local var, drop it
                self.drop_var(var, if_scope, line);
                continue;
            }
            let rhs = Rhs::new(var.clone());
            let parent_state = self.get_state(&rhs, parent_scope);
            //print("parent_state={}\n", parent_state);
            if(parent_state.is_moved()){
                let if_state = self.get_state(&rhs, if_scope);
                if(if_state.is_assigned()){
                    let else_state = self.get_state(&rhs, else_scope);
                    if(else_state.is_none()){
                        //self.drop_var(var, if_scope, line);
                        self.drop_var_real(var, line);
                        panic("aha");
                    }
                }
                //todo dont look child
                //already moved in parent, dont check sibling move
                rhs.drop();
                continue;
            }
            let else_state = self.get_state(&rhs, else_scope);
            if(else_state.is_moved()){
                //print("sibling2 {}\n", var);
                //else moved outer, drop in if
                self.drop_var(var, if_scope, line);
                //panic("moved in sibling {}", var);
            }
            rhs.drop();
        }
        outers.drop();
        //restore old scope
        for(let i = 0;i < visitor.scopes.len();++i){
            let st = visitor.scopes.get(i);
            self.scope_map.remove(st);
        }
        if(verbose){
            print("\n");
        }
        self.set_current(if_scope.parent);
        visitor.drop();
    }

    func drop_lhs(self, lhs: Expr*, ptr: LLVMOpaqueValue*){
        if(!self.is_drop_type(lhs)){
            return;
        }
        let lhs2 = Rhs::new(lhs, self);
        let state = self.get_state(&lhs2, self.get_scope());
        if(state.is_moved()){
            lhs2.drop();
            return;
        }
        if(print_drop_lhs){
            Logger::add(format("drop_lhs {:?} line: {}\n", lhs, lhs.line));
        }
        if(drop_lhs_enabled){
            let rt = self.get_type(lhs);
            self.drop_force(&rt, ptr, lhs.line, &lhs2);
            rt.drop();
        }
        lhs2.drop();
    }
}

//drop logic
impl Own{
    func check_partial(self, var: Variable*, scope: VarScope*, line: i32){
        //check if all fields moved
        //let rhs = Rhs::new(var);
        let rt = self.compiler.get_resolver().visit_type(&var.type);
        let decl = self.compiler.get_resolver().get_decl(&rt).unwrap();
        let fields = decl.get_fields();
        let moved_fields = List<String>::new();
        for fd in fields{
            let rhs = Rhs::new(var.clone(), fd.name.get().clone());
            let state = self.get_state(&rhs, scope);
            if(state.kind is StateType::MOVED){
                moved_fields.add(fd.name.get().clone());
            }else if(state.kind is StateType::MOVED_PARTIAL){
                self.get_resolver().err(var.line, "move of partial of partial");
            }
            rhs.drop();
        }
        let err = false;
        for fd in fields{
            if(!self.is_drop_type(&fd.type)){
                continue;
            }
            if(!moved_fields.contains(fd.name.get())){
                print("field '{:?}.{:?}' vline: {} not moved at: {}\n", var.name, fd.name.get(), var.line, line);
                err = true;
            }
        }
        if(err){
            self.compiler.get_resolver().err(line, "");
        }
        moved_fields.drop();
        rt.drop();
    }
    func drop_var(self, var: Variable*, scope: VarScope*, line: i32){
        if(var.is_self && is_drop_method(self.method)){
            return;
        }
        if(var.type.is_pointer()){
            //use get_state for each field
            return;
        }
        let rhs = Rhs::new(var.clone());
        let state = self.get_state(&rhs, scope);
        if(print_kind is PrintKind::Any){
            let info = scope.print_info();
            Logger::add(format("drop_var {:?} line: {} state: {:?} scope: {:?}\n", var, line,  state, info));
            info.drop();
        }

        if(state.kind is StateType::MOVED_PARTIAL){
            self.check_partial(var, scope, line);
            //self.compiler.get_resolver().err(var.line, format("var {} moved partially", var));
            rhs.drop();
            return;
        }
        if(state.is_moved()){
            rhs.drop();
            return;
        }
        if(print_kind is PrintKind::Valid){
            let tmp = scope.print_info();
            Logger::add(format("drop_var_real {:?} line: {} state: {:?} scope: {:?}\n", var, line,  state, tmp));
            tmp.drop();
        }
        let rt = self.compiler.get_resolver().visit_type(&var.type);
        self.drop_real(&rt, var.ptr, line, &rhs);
        rt.drop();
        rhs.drop();
    }
    func drop_var_real(self, var: Variable*, line: i32){
        if(print_kind is PrintKind::Valid){
            Logger::add(format("drop_var_real {:?}\n", var));
        }
        let rt = self.compiler.get_resolver().visit_type(&var.type);
        let rhs = Rhs::new(var.clone());
        self.drop_real(&rt, var.ptr, line, &rhs);
        rt.drop();
        rhs.drop();
    }
    func drop_obj(self, obj: Object*, scope: VarScope*, line: i32){
        let rhs = Rhs::new(obj.expr, self);
        let state = self.get_state(&rhs, scope);
        if(print_kind is PrintKind::Any){
            Logger::add(format("drop_obj {:?} state: {:?} oline: {} line: {}\n", obj.expr, state.kind, obj.expr.line, line));
        }
        if(state.is_moved()){
            rhs.drop();
            return;
        }
        if(print_kind is PrintKind::Valid){
            Logger::add(format("drop_obj_real {:?} state: {:?} oline: {} line: {}\n", obj.expr, state.kind, obj.expr.line, line));
        }
        let resolver = self.compiler.get_resolver();
        let rt = resolver.visit(obj.expr);
        self.drop_real(&rt, obj.ptr, line, &rhs);
        rt.drop();
        rhs.drop();
    }

    func drop_real(self, rt: RType*, ptr: LLVMOpaqueValue*, line: i32, rhs: Rhs*){
        if(!self.is_drop_type(&rt.type)){
            return;
        }
        if(drop_enabled){
            self.drop_force(rt, ptr, line, rhs);
        }
        if(print_drop_real){
            Logger::add(format("drop_real at: {} {:?}\n", line, rhs));
        }
    }
    func drop_force(self, rt: RType*, ptr: LLVMOpaqueValue*, line: i32, rhs: Rhs*){
        let proto = self.get_proto(rt);
        let args = [ptr];
        let ll = self.compiler.ll.get();
        LLVMBuildCall2(ll.builder, proto.ty, proto.val, args.ptr(), 1, "".ptr());
    }
    func get_proto(self, rt: RType*): FunctionInfo{
        let resolver = self.compiler.get_resolver();
        let decl = resolver.get_decl(rt).unwrap();
        let helper = DropHelper{resolver};
        let method = helper.get_drop_method(rt);
        if(method.is_generic){
            panic("generic {:?}", rt.type);
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
