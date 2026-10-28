import std/map
import std/hashmap
import std/stack
import std/io

import ast/ast
import ast/utils
import ast/printer

import resolver/resolver
import resolver/method_resolver
import resolver/exit
import resolver/derive
import resolver/drop_helper

import parser/own_visitor
import parser/own_helper
import parser/own_model

import backend/emitter


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

static drop_enabled: bool = true;
static drop_lhs_enabled: bool = true;
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
    }
}

struct Own{
    compiler: Emitter*;
    method: Method*;
    main_scope: i32;
    cur_scope: i32;
    scope_map: Map<i32, VarScope>;
    var_map: Map<i32, Variable>;
    //MATCH_CASE scope ids of the innermost open match (stack discipline
    //via begin_match/end_match): end_match merges non-jump arm marks up.
    match_arms: List<i32>;
    //payload binding id -> scrutinee record (see BindInfo): arm-end
    //rollback for bindings that never escaped.
    match_binds: Map<i32, BindInfo>;
    //Fmt::str keys of explicitly dropped places (see note_explicit_drop):
    //drop emission skips them so manual drops never double-fire.
    explicit_drops: Map<String, bool>;
    //Fmt::str keys of fields/elements whose MOVED mark was invalidated by a
    //whole-var (re)write (`x = X{..}` reinitializes every field of x, see
    //note_reinit). check_place skips exactly those marks. The marks stay in
    //the state map: block/loop merges and the drop machinery rely on the
    //accumulated marks, and removing them there would let a var whose
    //fields were moved out inside a loop be dropped whole (double free).
    //Entries stay for the rest of the method on purpose: re-arming them on a
    //later move would report the post-loop use in
    //`while(c){ send(x.f); x = X{..}; }` `send(x.f);` as a use after move,
    //but that use is live (the last iteration ended with the reinit).
    //Consequence: a *second* move of such a place after the whole-var write
    //is not diagnosed (doc/ownership.txt residual).
    reinit_places: Map<String, bool>;
}

impl Drop for Own{
    func drop(*self){
        self.scope_map.drop();
        self.var_map.drop();
        self.match_arms.drop();
        self.match_binds.drop();
        self.explicit_drops.drop();
        self.reinit_places.drop();
        Logger::exit(&self);
    }
}

impl Own{
    func new(c: Emitter*, m: Method*): Own{
        //print("print_kind={:?}\n", print_kind);
        let exit = Exit::get_exit_type(m.body.get());
        let main_scope = VarScope::new(ScopeType::MAIN, m.line, exit);
        let res = Own{
            compiler: c,
            method: m,
            main_scope: main_scope.id,
            cur_scope: main_scope.id,
            scope_map: Map<i32, VarScope>::new(),
            var_map: Map<i32, Variable>::new(),
            match_arms: List<i32>::new(),
            match_binds: Map<i32, BindInfo>::new(),
            explicit_drops: Map<String, bool>::new(),
            reinit_places: Map<String, bool>::new()
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
            if((kind is ScopeType::WHILE || kind is ScopeType::FOR) && pair.b.is_moved()){
                scope.pre_moved.add(Fmt::str(pair.a), true);
            }
        }
        scope.parent = parent.id;
        let id = scope.id;      
        self.scope_map.add(scope.id, scope);
        if(kind is ScopeType::MATCH_CASE){
            self.match_arms.add(id);
        }
        self.set_current(id);
        return id;
    }
    func add_scope(self, kind: ScopeType, stmt: Body*): i32{
        let exit = Exit::get_exit_type(stmt);
        return self.add_scope(kind, stmt.line(), exit, false);
    }
    //A desugared for-each body ends with the opaque `std::internal_block!`
    //placeholder, so Exit reads it as falling through even when the real
    //block ends with break/continue/return. The emitter resolves the real
    //exit through the block map; record that one, else end_scope emits the
    //scope-end drops into the already terminated block (invalid IR) and
    //check_loop_moves reports a break-only move as repeated.
    func add_scope(self, kind: ScopeType, stmt: Body*, exit: Exit): i32{
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
        let rt = self.get_resolver().visit(expr);
        return rt;
    }
    //register var & obj
    func is_drop_type(self, type: Type*): bool{
        let helper = DropHelper::new(self.get_resolver());
        return helper.is_drop_type(type);
    }
    func is_drop_type(self, expr: Expr*): bool{
        let rt = self.get_type(expr);
        let res = self.is_drop_type(&rt.type);
        return res;
    }
    func is_drop_or_ptr(self, type: Type*): bool{
        if(type.is_pointer()){
            return self.is_drop_type(type.elem());
        }
        return self.is_drop_type(type);
    }
    func add_prm(self, p: Param*, ptr: LLVMPtr){
        //print("add_prm {}:{} line={}\n", p.name, p.type, p.line);
        if(!self.is_drop_or_ptr(&p.type)) return;
        let var = Variable{
            name: p.name.clone(),
            type: p.type.clone(),
            ptr: ptr,
            id: p.id,
            line: p.line,
            scope: self.get_scope().id,
            is_self: p.is_self,
            is_captured: p.is_captured
        };
        self.get_scope().vars.add(p.id);
        self.get_scope().state_map.add(Rhs::new(var.clone()), StateType::NONE);
        self.var_map.add(p.id, var);
    }
    func add_var(self, f: Fragment*, ptr: LLVMPtr){
        let rt = self.get_resolver().visit_frag(f);
        if(!self.is_drop_or_ptr(&rt.type)){
            return;
        } 
        let var = Variable{
            name: f.name.clone(),
            type: rt.type.clone(),
            ptr: ptr,
            id: f.id,
            line: f.line,
            scope: self.get_scope().id,
            is_self: false,
            is_captured: false
        };
        self.get_scope().vars.add(var.id);
        self.get_scope().state_map.add(Rhs::new(var.clone()), StateType::NONE);
        self.var_map.add(var.id, var);
        self.do_move(&f.rhs);
    }
    func add_iflet_var(self, arg: ArgBind*, ty: Type*, ptr: LLVMPtr){
        if(!self.is_drop_or_ptr(ty)) return;
        /*if(rhs_ty.is_pointer()){
            self.get_resolver().err(arg.line, format("can't deref member from ptr '{}'", arg.name));
        }*/
        let var = Variable{
            name: arg.name.clone(),
            type: ty.clone(),
            ptr: ptr,
            id: arg.id,
            line: arg.line,
            scope: self.get_scope().id,
            is_self: false,
            is_captured: false
        };
        self.get_scope().vars.add(var.id);
        self.get_scope().state_map.add(Rhs::new(var.clone()), StateType::NONE);
        self.var_map.add(var.id, var);
    }
    func add_obj(self, expr: Expr*, ptr: LLVMPtr, type: Type*){
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

    //True when if-let's scrutinee is an owned temporary the engine already
    //tracks as an object (not a named place, not a borrow). Only such a
    //scrutinee needs the explicit else-path drop (ElseScrutinee): the
    //engine would drop it at the parent scope end, save for the move mark
    //if-let plants for the match path; a named place is instead handled by
    //the arm rollback (mark_scrutinee/end_match_arm).
    func is_temp_scrutinee(self, scr: Expr*): bool{
        if let Expr::Access(scp, name) = scr{
            let scp_rt = self.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_some() && self.var_map.get(&scp_rt.vh.get().id).is_some()){
                return false;
            }
        }else{
            let rt = self.get_resolver().visit(scr);
            if(rt.vh.is_some() && (scr is Expr::Name || scr is Expr::Unary) && self.var_map.get(&rt.vh.get().id).is_some()){
                return false;
            }
        }
        let scope = self.get_scope();
        while(true){
            for obj in &scope.objects{
                if(obj.expr.id == scr.id){
                    return true;
                }
            }
            if(scope.parent == -1){
                break;
            }
            scope = self.get_scope(scope.parent);
        }
        return false;
    }
    //Explicit, path-local drop of an owned temporary (if-let else path,
    //see ElseScrutinee). There is no state to consult: the emitter proved
    //this path owns the value, and the temporary is suppressed on the
    //other path by the match mark.
    func drop_temp(self, rt: RType*, ptr: LLVMPtr, line: i32, scr: Expr*){
        let rhs = Rhs::EXPR{scr};
        self.drop_real(rt, ptr, line, &rhs);
    }
    //A payload binding copies the scrutinee's bytes; from birth the
    //binding owns the copy, so the source must never drop it (else the
    //same buffer dies twice: `let s = File::read_string(..)?` double-freed).
    //Temps are marked consumed in their own scope. Named scrutinees are
    //marked too (see mark_scrutinee) when the payload is drop-tracked and
    //the scrutinee is a value, not a borrow. Legal callees cannot hand out
    //owned aliases of borrows (`return *o` on drop types is rejected, and
    //generics are instantiation-checked), so a temp derived from a legal
    //call needs no owner tracking. Remaining hole is `extern`/unsafe
    //aliasing fns only (no body to check -- deferred, see handoff).
    //Bind from the owner directly, or clone at the site (visit_call does
    //this for lambda types). Mirrors Rhs::new's named-place recognition,
    //but never panics: an unregistered vh just means "not provably
    //named", and for anything but a proven temp we do nothing.
    func consume_match_temp(self, scr: Expr*, track_named: bool, bind_id: i32){
        if let Expr::Access(scp, name) = scr{
            let scp_rt = self.get_resolver().visit(scp.get());
            let named = scp_rt.vh.is_some() && self.var_map.get(&scp_rt.vh.get().id).is_some();
            if(named){
                let vid = scp_rt.vh.get().id;
                if(track_named){
                    self.mark_scrutinee(vid, scr, bind_id);
                }
                return;
            }
        }else{
            let rt = self.get_resolver().visit(scr);
            let named = rt.vh.is_some() && (scr is Expr::Name || scr is Expr::Unary) && self.var_map.get(&rt.vh.get().id).is_some();
            if(named){
                let vid = rt.vh.get().id;
                if(track_named){
                    self.mark_scrutinee(vid, scr, bind_id);
                }
                return;
            }
        }
        let rhs = Rhs::EXPR{scr};
        let scope = self.get_scope();
        while(true){
            for obj in &scope.objects{
                if(obj.expr.id == scr.id){
                    self.update_state(rhs, StateType::MOVED{scr.line}, scope);
                    return;
                }
            }
            if(scope.parent == -1){
                break;
            }
            scope = self.get_scope(scope.parent);
        }
    }

    //A payload binding copies the named scrutinee's bytes; from birth the
    //binding owns the copy, so the scrutinee must never drop it (else the
    //same buffer dies twice). Mark the scrutinee consumed in the current
    //(arm) scope: sibling arms snapshot clean states, and end_match merges
    //non-jump arm marks to the parent for post-match drops.
    func mark_scrutinee(self, vid: i32, scr: Expr*, bind_id: i32){
        if(self.var_map.get(&vid).is_some()){
            let scope = self.get_scope();
            if(verbose){
                print("mark_scrutinee scope\n");
            }
            //pre-state comes from the parent: if-let moves the scrutinee
            //into the arm scope first (do_move), and nested binds see the
            //outer arm's marks there. Both must read as moved.
            let parent = self.get_scope(scope.parent);
            let v = self.get_var(vid).clone();
            let key = Rhs::new(v.clone());
            let pre = self.get_state(&key, parent);
            self.match_binds.add(bind_id, BindInfo{scr: vid, pre: pre.kind.clone(), line: scr.line});
            self.update_state(Rhs::new(v), StateType::MOVED{scr.line}, scope);
        }
    }

    //Arm-end rollback for inspect-only arms (see BindInfo): for each
    //distinct recorded scrutinee in this arm, if every recorded binding
    //is still unmoved, the scrutinee is untouched since the bind, and it
    //was unmoved before, roll back: suppress the aliasing bindings and
    //restore the scrutinee. The scrutinee then drops (and reads) normally
    //with no leak and no false use-after-move. Anything escaped, moved,
    //reassigned, unregistered, or pre-moved keeps the conservative marks.
    func end_match_arm(self, scope: VarScope*){
        if(verbose){
            print("end_match_arm scope\n");
        }
        let n = scope.vars.len();
        let i = 0;
        while(i < n){
            let bid = *scope.vars.get(i);
            let rec = self.match_binds.get(&bid);
            if(rec.is_some()){
                self.maybe_rollback(rec.unwrap().scr, scope);
            }
            i += 1;
        }
    }
    func maybe_rollback(self, scr: i32, scope: VarScope*){
        //all recorded bindings of scr in this arm must be registered and
        //unmoved; anything else (escaped, partial, unregistered) vetoes.
        let n = scope.vars.len();
        let i = 0;
        let line = -1;
        let pre_none = false;
        let first = true;
        while(i < n){
            let bid = *scope.vars.get(i);
            let rec = self.match_binds.get(&bid);
            if(rec.is_some() && rec.unwrap().scr == scr){
                if(self.var_map.get(&bid).is_none()){
                    if(verbose){
                        print("rollback veto: binding unregistered\n");
                    }
                    return;
                }
                let bv = self.get_var(bid).clone();
                let bkey = Rhs::new(bv.clone());
                let bst = self.get_state(&bkey, scope);
                //auto-drop owns bv/bkey (both drop types via String): no
                //manual drops needed, exactly once at scope end.
                if(!(bst.kind is StateType::NONE)){
                    if(verbose){
                        print("rollback veto: binding moved\n");
                    }
                    return;
                }
                if(first){
                    line = rec.unwrap().line;
                    pre_none = rec.unwrap().pre is StateType::NONE;
                    first = false;
                }
            }
            i += 1;
        }
        if(first){
            if(verbose){
                print("rollback veto: no bindings in scope\n");
            }
            return;
        }
        if(!pre_none){
            if(verbose){
                print("rollback veto: pre moved\n");
            }
            return;
        }
        //scrutinee untouched since the bind mark?
        if(self.var_map.get(&scr).is_none()){
            if(verbose){
                print("rollback veto: scrutinee unregistered\n");
            }
            return;
        }
        let sv = self.get_var(scr).clone();
        let skey = Rhs::new(sv.clone());
        let sst = self.get_state(&skey, scope);
        if let StateType::MOVED(mline) = sst.kind{
            if(mline != line){
                if(verbose){
                    print("rollback veto: scrutinee moved elsewhere\n");
                }
                return;
            }
        }else{
            if(verbose){
                print("rollback veto: scrutinee not in bind mark\n");
            }
            return;
        }
        //roll back: bindings suppressed, scrutinee restored.
        if(verbose){
            print("rollback scope\n");
        }
        let j = 0;
        while(j < n){
            let bid2 = *scope.vars.get(j);
            let rec2 = self.match_binds.get(&bid2);
            if(rec2.is_some() && rec2.unwrap().scr == scr){
                let bv2 = self.get_var(bid2).clone();
                self.update_state(Rhs::new(bv2), StateType::MOVED{scope.line}, scope);
            }
            j += 1;
        }
        let sv2 = self.get_var(scr).clone();
        self.update_state(Rhs::new(sv2), StateType::NONE, scope);
    }

    //Match-arm scope stack discipline (see match_arms): nested matches
    //merge only the arms they opened.
    func begin_match(self): i64{
        return self.match_arms.len();
    }
    func end_match(self, mark: i64){
        let parent = self.get_scope();
        let n = self.match_arms.len();
        let i = mark;
        while(i < n){
            let arm = self.get_scope(*self.match_arms.get(i));
            if(!arm.exit.is_jump()){
                for pair in &arm.state_map{
                    if(pair.b is StateType::MOVED || pair.b is StateType::MOVED_PARTIAL){
                        self.update_state(pair.a.clone(), pair.b.clone(), parent);
                    }
                }
            }
            i += 1;
        }
        while(self.match_arms.len() > mark){
            self.match_arms.pop_back();
        }
    }

    //Mark a match-arm yielded place as moved: the arm value is memcpy'd
    //into the match result, so the place must not also die with the arm.
    //VAR places with registered ids only; anything else keeps today's
    //behavior. Never panics (membership-checked before get_var). Non-drop
    //types are unaffected: check() and drop emission both skip them.
    func mark_yield(self, e: Expr*){
        if(!(e is Expr::Name || e is Expr::Unary)){
            //yielded temp (e.g. `_ => String::new(..)`): the value is
            //memcpy'd to the match result, so the temp must not drop it
            //afterwards (nor drop garbage when another arm ran).
            self.update_state(Rhs::EXPR{e}, StateType::MOVED{e.line}, self.get_scope());
            return;
        }
        let rt = self.get_resolver().visit(e);
        if(rt.vh.is_none()){
            return;
        }
        let id = rt.vh.get().id;
        if(self.var_map.get(&id).is_none()){
            return;
        }
        let v = self.get_var(id).clone();
        self.update_state(Rhs::new(v), StateType::MOVED{e.line}, self.get_scope());
    }

    // func do_move(self, block: Block*){
    // }

    //Record a move of drop data out through a pointer (struct field of a
    //borrowed place, or deref). Heal by reassigning the same place before
    //scope end; leftovers error in check_ptr_moves. No state marks: drops
    //and validators stay exactly as before.
    func note_ptr_move(self, rhs: Rhs*, line: i32){
        let scope = self.get_scope();
        let key = Fmt::str(rhs);
        scope.ptr_left.add(PtrMove{place: key, line: line});
    }
    //Record a deref move (*p, *boxed) under the pointer var's key, so a
    //later *p = x heals it. Falls through (false) when unresolvable.
    func note_deref_move(self, e: Expr*, line: i32): bool{
        let rt = self.get_resolver().visit(e);
        if(rt.vh.is_some() && self.var_map.get(&rt.vh.get().id).is_some()){
            let v = self.get_var(rt.vh.get().id).clone();
            let tmp = Rhs::new(v);
            self.note_ptr_move(&tmp, line);
            return true;
        }
        return false;
    }
    //A reassignment heals a recorded pointer move on the same place
    //(take(p.s); p.s = x). Only same-shape keys match, so whole-var
    //reassigns don't heal field moves and vice versa.
    func clear_ptr_move(self, rhs: Rhs*, scope: VarScope*){
        let key = Fmt::str(rhs);
        let i = 0;
        while(i < scope.ptr_left.len()){
            if(scope.ptr_left.get(i).place.eq(&key)){
                scope.ptr_left.remove(i);
            }else{
                i += 1;
            }
        }
    }
    //Scope-end rule (see note_ptr_move): every recorded move must have
    //been healed by reassign. Unconditional-in-scope; conditional heals
    //still error (documented limitation).
    func check_ptr_moves(self, scope: VarScope*, line: i32){
        if(scope.ptr_left.empty()){
            return;
        }
        let first = scope.ptr_left.get(0);
        self.get_resolver().err(line, format!("move of drop type out of pointer without reassign: {:?}", first.place));
    }
    //Move leftover records to the parent scope (see above). Scopes without
    //a parent check instead of bubbling.
    func bubble_ptr_moves(self, scope: VarScope*){
        if(scope.ptr_left.empty()){
            return;
        }
        if(scope.parent == -1){
            self.check_ptr_moves(scope, scope.line);
            return;
        }
        let parent = self.get_scope(scope.parent);
        for(let i = 0;i < scope.ptr_left.len();++i){
            let e = scope.ptr_left.get(i);
            parent.ptr_left.add(PtrMove{place: e.place.clone(), line: e.line});
        }
        scope.ptr_left.clear();
    }
    //The literal integer index of `arr[N]`, or none for anything else: a
    //dynamic index, a slice (`arr[a..b]`), a non-int literal. A constant
    //index makes the element a trackable place (see Rhs::new).
    func const_index(self, aa: ArrAccess*): Option<i32>{
        if(aa.idx2.is_some()){
            return Option<i32>::new();
        }
        if let Expr::Lit(lit) = aa.idx.get(){
            if(lit.kind is LitKind::INT){
                let trimmed = lit.trim_suffix();
                let normal = trimmed.replace("_", "");
                if(normal.str().starts_with("0x") || normal.str().starts_with("-0x")){
                    let r = i64::parse_hex(normal.str());
                    if(r.is_ok()){
                        return Option<i32>::new(r.unwrap() as i32);
                    }
                    return Option<i32>::new();
                }
                let r = i64::parse(normal.str());
                if(r.is_ok()){
                    return Option<i32>::new(r.unwrap() as i32);
                }
            }
        }
        return Option<i32>::new();
    }
    func do_move(self, expr: Expr*){
        let rt = self.get_type(expr);
        if(!self.is_drop_type(&rt.type)){
            return;
        }
        if(verbose){
            let mv = Move{
                lhs: Option<Moved>::new(),
                rhs: Moved::new(expr, self),
                line: expr.line
            };
            print("do_move {:?}\n", &mv);
        }
        let rhs = Rhs::new(expr, self);
        //A captured value lives in the closure object and the method that
        //borrows it may run many times: moving it out would hand the same
        //allocation to the callee on the first call and leave a stale field
        //for the drop. See doc/closures.txt section 9.
        if(self.is_captured_rhs(&rhs)){
            self.get_resolver().err(expr, "cannot move out of a captured value");
        }
        //Any place rooted at an index (`arr[i]`, `arr[i].f`, `p[i].a`) is
        //movable only when it *is* a tracked element place: a constant index
        //into a local array (Rhs::INDEX, see Rhs::new). Everything else has
        //no place state, so the aggregate would keep dropping a value that
        //already left (the same allocation freed twice). Refuse those: the
        //aggregate keeps owning the element. (This also covers cases like
        //`send(p[0].a)`, which used to compile and drop that field twice.)
        //Reads and `arr[i].clone()` are unaffected.
        if(self.is_index_place(expr) && !(rhs is Rhs::INDEX)){
            self.get_resolver().err(expr, "cannot move out of an array element");
        }
        if let Rhs::FIELD(scp, name)=&rhs{
            if(!move_ptr_field && scp.type.is_pointer()){
                self.get_resolver().err(expr, "move out of pointer");
            }
            //moving drop data out through a borrowed struct must heal by
            //reassign before scope end (see check_ptr_moves); the mark
            //stays for the existing validator.
            if(scp.type.is_pointer()){
                self.note_ptr_move(&rhs, expr.line);
            }
        }
        //deref of drop data (*p, *boxed): record for the heal rule, but
        //keep the normal VAR mark (it suppresses autos elsewhere).
        if let Expr::Unary(op, inner) = expr{
            if(op.eq("*")){
                self.note_deref_move(inner.get(), expr.line);
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
    }
    //explicit drop target: record it so drop emission skips the auto
    //duplicate (see drop_var/drop_obj). No marks: destroying in place is
    //not a move, so post-uses and validators stay quiet; reassignment
    //clears the record via update_state.
    func note_explicit_drop(self, expr: Expr*){
        if let Expr::Access(scp, name) = expr{
            let scp_rt = self.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_none() || self.var_map.get(&scp_rt.vh.get().id).is_none()){
                return;
            }
            let sv = self.get_var(scp_rt.vh.get().id).clone();
            let rf = Rhs::FIELD{sv.clone(), name.clone()};
            let fkey = Fmt::str(&rf);
            self.explicit_drops.add(fkey, true);
            let rs = Rhs::new(sv);
            let skey = Fmt::str(&rs);
            self.explicit_drops.add(skey, true);
            return;
        }
        let rt = self.get_resolver().visit(expr);
        let named = rt.vh.is_some() && (expr is Expr::Name || expr is Expr::Unary) && self.var_map.get(&rt.vh.get().id).is_some();
        if(!named){
            return;
        }
        let v = self.get_var(rt.vh.get().id).clone();
        let r = Rhs::new(v);
        let key = Fmt::str(&r);
        self.explicit_drops.add(key, true);
    }
    //#[returns_alias(p)] (on plain or extern methods): the return value
    //may alias the borrow passed as p. The owner is consumed at the call
    //so post-uses error and scope end skips its drop; the fresh return
    //drops normally. Exactly-once moves from owner to return.
    //Non-borrow or unresolvable args are a loud error (silence would be
    //a hole); non-heap owners need no protection and pass through.
    //Mirrored in backend visit_call2 and own_visitor visit_call so arm
    //merges agree (same discipline as note_explicit_drop).
    func consume_alias_args(self, mc: Call*, target: Method*, line: i32){
        let opt = target.attr.find("returns_alias");
        if(opt.is_none()){
            return;
        }
        let at = opt.unwrap();
        if(!at.is_call){
            self.get_resolver().err(line, "returns_alias expects a parameter list");
        }
        //mirror visit_call2 receiver alignment: static-with-self calls
        //carry the receiver in args[0].
        let argIdx = 0;
        if(target.self.is_some() && mc.is_static){
            argIdx = 1;
        }
        let paramIdx = 0;
        while(paramIdx < target.params.len() && argIdx < mc.args.len()){
            let prm = target.params.get(paramIdx);
            if(self.is_alias_param(at, line, &prm.name)){
                self.consume_alias_arg(mc.args.get(argIdx));
            }
            paramIdx += 1;
            argIdx += 1;
        }
    }
    func is_alias_param(self, at: Attribute*, line: i32, name: String*): bool{
        for ae in &at.args{
            if let Expr::Name(nm) = ae{
                if(nm.str().eq(name.str())){
                    return true;
                }
            }else{
                self.get_resolver().err(line, "returns_alias expects parameter names");
            }
        }
        return false;
    }
    func consume_alias_arg(self, arg: Expr*){
        if let Expr::Unary(op, inner) = arg{
            if(op.eq("&")){
                let rt = self.get_resolver().visit(inner.get());
                //no heap behind the borrow: nothing to protect.
                if(!self.is_drop_or_ptr(&rt.type)){
                    return;
                }
                let ok = rt.vh.is_some() && self.var_map.get(&rt.vh.get().id).is_some();
                if(!ok){
                    self.get_resolver().err(arg, "returns_alias argument must be a borrow of a named place");
                }
                self.do_move(inner.get());
                return;
            }
        }
        self.get_resolver().err(arg, "returns_alias argument must be a borrow of a named place");
    }
    //move rhs
    //A loop body's merged state is the state that reaches the back-edge. A
    //move of a place declared *outside* the loop is emitted once but runs on
    //every iteration, so the next iteration would use the moved value (a
    //double free at run time: `let s = String::new(..); while(c){ send(s); }`
    //did that on v1.20). Report it here, at the line of the move.
    //Places that were already moved when the loop was entered are skipped:
    //using one inside the body already errored as a use after move (and a
    //for-each's consumed collection is exactly that shape, unused in the
    //body).
    func check_loop_moves(self, scope: VarScope*){
        let outers: List<Droppable> = self.get_outer_vars(scope);
        for dr in &outers{
            if let Droppable::OBJ(obj)=dr{
                continue;
            }
            let var = dr.as_var();
            if(var.scope == scope.id){
                //declared in the loop body: a fresh value each iteration
                continue;
            }
            let rhs = Rhs::new(var.clone());
            //A whole-var write *in this body* leaves the var live even if a
            //*field* of it was moved after the write (std/hashmap's rehash
            //reassigns `node` from `node.next` and then hands its fields to
            //insert). `scope.assigned` only holds writes made in this scope,
            //so an inherited ASSIGNED (a write before the loop) does not
            //excuse a field moved in the body. The field marks stay either
            //way, so reading one before the next write still errors.
            let aopt = scope.assigned.get(&Fmt::str(&rhs));
            if(aopt.is_some() && *aopt.unwrap() >= scope.line){
                continue;
            }
            //Only a move made *in this body* is this loop's problem: a place
            //that arrived moved (or partially moved) was moved before the loop
            //and the next iteration does not use it again (if it did, the read
            //would already be a use after move).
            let mline = -1;
            for pair in &scope.state_map{
                if(mline != -1){
                    continue;
                }
                if(!(pair.b is StateType::MOVED)){
                    continue;
                }
                if(self.place_root_id(pair.a) != var.id){
                    continue;
                }
                if(scope.pre_moved.contains(&Fmt::str(pair.a))){
                    continue;
                }
                if let StateType::MOVED(l) = pair.b{
                    mline = *l;
                }
            }
            if(mline == -1){
                continue;
            }
            self.get_resolver().err(mline, format("`{}` is moved inside a loop; the next iteration would use it after the move", var.name));
        }
    }
    //Is this place (or a field/element of it) a captured value of the
    //lambda method being emitted? See Param.is_captured.
    func is_captured_rhs(self, rhs: Rhs*): bool{
        if let Rhs::VAR(v) = rhs{
            return v.is_captured;
        }
        if let Rhs::FIELD(scp, _) = rhs{
            return scp.is_captured;
        }
        if let Rhs::INDEX(scp, _) = rhs{
            return scp.is_captured;
        }
        return false;
    }
    func do_assign(self, lhs: Expr*, rhs: Expr*){
        let scope = self.get_scope();
        let rt = self.get_type(rhs);
        if(!self.is_drop_type(&rt.type)){
            return;
        }
        let lhs_rhs = Rhs::new(lhs, self);
        if(self.is_captured_rhs(&lhs_rhs)){
            //the borrowed field is not dropped here, so a write would leak the
            //new value (and the old one would still be dropped by the
            //object). No `mut` capture in v1; see doc/closures.txt.
            self.get_resolver().err(lhs, "cannot assign to a captured value");
        }
        if(verbose){
            let mv = Move{Option::new(Moved::new(lhs, self)), Moved::new(rhs, self), lhs.line};
            print("do_move {:?} line:{}\n", &mv, lhs.line);
        }
        self.update_state(rhs, &rt, StateType::MOVED{rhs.line}, scope);
        let rt_lhs = self.get_type(lhs);
        //A whole-var write reinitializes every field/element of the var, so
        //the move marks of its sub-places are stale (see note_reinit).
        let lhs_place = self.place_rhs(lhs);
        if(lhs_place.is_some()){
            self.note_reinit(&lhs_place.unwrap(), scope);
        }
        self.update_state(lhs, &rt_lhs, StateType::ASSIGNED, scope);
        scope.assigned.add(Fmt::str(&lhs_rhs), lhs.line);
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
        //reassignment starts fresh ownership: clear any explicit-drop
        //record so the new value drops normally.
        if(kind is StateType::ASSIGNED){
            let rkey = Fmt::str(&rhs);
            self.explicit_drops.remove(&rkey);
            self.clear_ptr_move(&rhs, scope);
        }
        //todo remove self param
        scope.state_map.add(rhs, kind);
    }
    //A whole-var (re)write reinitializes every field/element of the var:
    //`node = next` after `insert(node.key, ..)` moved the fields out (the
    //loop pattern in std/hashmap's rehash). Any move mark of a sub-place of
    //that var recorded before the write is therefore stale, and check_place
    //must not report it as a use after move. Remember those places here --
    //the marks themselves stay (see the field declaration): a plain
    //straight-line case still drops the moved-out *old* value correctly, and
    //the loop-exit state keeps naming the fields that really are moved.
    //Only a whole *local* has this shape: its fields/elements are all keyed
    //by the variable id, and the whole-var write really does cover each of
    //them. A field/element write marks that place ASSIGNED itself, so it
    //needs no entry (and its nested places are not keyed separately, see
    //Rhs::FIELD/INDEX).
    func note_reinit(self, rhs: Rhs*, scope: VarScope*){
        if let Rhs::VAR(v) = rhs{
            for pair in &scope.state_map{
                if(!(pair.b is StateType::MOVED)){
                    continue;
                }
                if let Rhs::FIELD(scp, name) = pair.a{
                    if(scp.id == v.id){
                        let place = pair.a.clone();
                        self.reinit_places.add(Fmt::str(&place), true);
                    }
                }
                if let Rhs::INDEX(scp, idx) = pair.a{
                    if(scp.id == v.id){
                        let place = pair.a.clone();
                        self.reinit_places.add(Fmt::str(&place), true);
                    }
                }
            }
        }
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
            return;
        }
        let scope = self.get_scope();
        if(print_check){
            print("check {:?} line:{}\n", expr, expr.line);
        }
        let rhs = Rhs::new(expr, self);
        let state = self.get_state(&rhs, scope);
        if let StateType::MOVED(line)=state.kind{
            // let scope_str = self.get_scope(self.main_scope).print(self);
            // print("{}\n", scope_str);
            // scope_str.drop();
            let tmp = printMethod(self.method);
            self.get_resolver().err(expr, format("use after move in {}:{} {:?}", tmp, line, expr));
        }
    }
    //Use after move through a *place* -- the counterpart of check() for
    //whole locals. A struct/tuple field or an array element that was moved
    //out is dead: reading it, writing a part of it, or moving it a second
    //time is a use after move (the aggregate still owns the bytes, but the
    //value is gone). The one legal use is a whole-place *write*
    //(`arr[i] = v`, `f.a = v`): it reinitializes the place, exactly like a
    //whole-local write (`x = v`), which is why visit_name/check are called
    //with check=false from Emitter::get_lhs and these two callers do the
    //same.
    func check_place(self, expr: Expr*){
        if(print_check){
            print("check_place {:?} line:{}\n", expr, expr.line);
        }
        let opt = self.place_rhs(expr);
        if(opt.is_none()){
            //Untracked place (`s[i]`, `p[i]`, a nested index, a bare deref):
            //no state to consult, and moves out of it are refused in
            //do_move. A plain local is check()'s job.
            return;
        }
        let rhs = opt.unwrap();
        if(!(rhs is Rhs::FIELD || rhs is Rhs::INDEX)){
            return;
        }
        let state = self.get_state(&rhs, self.get_scope());
        if let StateType::MOVED(line)=state.kind{
            if(self.reinit_places.get(&Fmt::str(&rhs)).is_some()){
                //the mark predates a whole-var (re)write of the base, so the
                //place is live again (see note_reinit).
                return;
            }
            let tmp = printMethod(self.method);
            self.get_resolver().err(expr, format("use after move in {}:{} {:?}", tmp, line, expr));
        }
    }
    //Rhs::new restricted to the two *tracked* place kinds (FIELD/INDEX) and
    //made total: a vh that var_map does not know (a `*self` base, a global,
    //any place the engine never registered) is a place with no state, not an
    //error -- Rhs::new itself panics on those, so it must not be used on an
    //expression the emitter is free to hand us (see consume_match_temp for
    //the same guard on the match path).
    func place_rhs(self, expr: Expr*): Option<Rhs>{
        if let Expr::Access(scp, name)=expr{
            let scp_rt = self.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_some() && self.var_map.get(&scp_rt.vh.get().id).is_some()){
                let v = self.get_var(scp_rt.vh.get().id);
                return Option::new(Rhs::FIELD{v.clone(), name.clone()});
            }
            if let Expr::MacroCall(mc) = scp.get(){
                if(Utils::is_call(mc, "ptr", "deref") && mc.args.len() > 0){
                    let irt = self.get_resolver().visit(mc.args.get(0));
                    if(irt.vh.is_some() && self.var_map.get(&irt.vh.get().id).is_some()){
                        let iv = self.get_var(irt.vh.get().id);
                        return Option::new(Rhs::FIELD{iv.clone(), name.clone()});
                    }
                }
            }
            return Option<Rhs>::none();
        }
        if let Expr::ArrAccess(aa) = expr{
            if(aa.arr.get() is Expr::Name){
                let opt = self.const_index(aa);
                if(opt.is_some()){
                    let art = self.get_resolver().visit(aa.arr.get());
                    if(art.type.is_array() && art.vh.is_some() && self.var_map.get(&art.vh.get().id).is_some()){
                        let av = self.get_var(art.vh.get().id);
                        return Option::new(Rhs::INDEX{scp: av.clone(), idx: opt.unwrap()});
                    }
                }
            }
        }
        let rt = self.get_resolver().visit(expr);
        if(rt.vh.is_some() && (expr is Expr::Name || expr is Expr::Unary) && self.var_map.get(&rt.vh.get().id).is_some()){
            let v = self.get_var(rt.vh.get().id);
            return Option::new(Rhs::VAR{v.clone()});
        }
        return Option<Rhs>::none();
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
            if(rhs is Rhs::FIELD || rhs is Rhs::INDEX){
                return State::new(StateType::NONE, scope);
            }
            print("{:?}\n", self.get_scope(self.main_scope).print(self));
            panic("no state {:?} from {:?}", rhs, scope.kind);
        }
        let state: StateType = *opt.unwrap();
        if(rhs is Rhs::FIELD || rhs is Rhs::INDEX){
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
                //an element of a tracked array (constant index) behaves
                //exactly like a field for the partial-move rollup
                if let Rhs::INDEX(scp, idx) = pair.a{
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
        self.check_ptr_moves(scope, line);
        let drops: List<Droppable> = self.get_outer_vars(scope);
        for dr in &drops{
            self.drop_any(dr, scope, line);
        }
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

    //drop vars & objs until the loop (shared by break and continue)
    func do_jump_drops(self, line: i32){
        let scope = self.get_scope();
        let drops = self.get_outer_vars_loop(scope);
        for dr in &drops{
            self.drop_any(dr, scope, line);
        }
    }
    //the innermost enclosing while/for of `scope`, if any
    func enclosing_loop(self, scope: VarScope*): Option<VarScope*>{
        let cur = scope.parent;
        while(cur != -1){
            let sc = self.get_scope(cur);
            if(sc.kind is ScopeType::WHILE || sc.kind is ScopeType::FOR){
                return Option::new(sc);
            }
            cur = sc.parent;
        }
        return Option<VarScope*>::new();
    }
    //is `inner` the loop scope `outer` or one of its descendants? A place
    //declared inside the loop body is fresh (or dead) each iteration.
    func scope_within(self, inner: i32, outer: i32): bool{
        let cur = inner;
        while(cur != -1){
            if(cur == outer){
                return true;
            }
            let sc = self.get_scope(cur);
            cur = sc.parent;
        }
        return false;
    }
    //the id of the variable a place is rooted at (-1 for a temporary)
    func place_root_id(self, rhs: Rhs*): i32{
        if let Rhs::VAR(v) = rhs{
            return v.id;
        }
        if let Rhs::FIELD(scp, _) = rhs{
            return scp.id;
        }
        if let Rhs::INDEX(scp, _) = rhs{
            return scp.id;
        }
        return -1;
    }
    //the scope a place's variable was declared in (-1 for a temporary)
    func rhs_var_scope(self, rhs: Rhs*): i32{
        if let Rhs::VAR(v) = rhs{
            return v.scope;
        }
        if let Rhs::FIELD(scp, _) = rhs{
            return scp.scope;
        }
        if let Rhs::INDEX(scp, _) = rhs{
            return scp.scope;
        }
        return -1;
    }
    //the variable a place is rooted at, for diagnostics (the Rhs Debug form
    //prints the whole Variable struct)
    func rhs_var_name(self, rhs: Rhs*): String{
        if let Rhs::VAR(v) = rhs{
            return v.name.clone();
        }
        if let Rhs::FIELD(scp, _) = rhs{
            return scp.name.clone();
        }
        if let Rhs::INDEX(scp, _) = rhs{
            return scp.name.clone();
        }
        return "?".str();
    }
    //record a moved place on a loop's jump-path list (dedupe by Rhs key)
    func note_loop_jump(self, list: List<LoopMove>*, rhs: Rhs*, line: i32){
        let key = Fmt::str(rhs);
        for pm in list{
            if(pm.key.eq(&key)){
                return;
            }
        }
        list.add(LoopMove{key: key, name: self.rhs_var_name(rhs), line: line});
    }
    func do_continue(self, line: i32){
        //A `continue` reaches the loop's back-edge, so what it moved is part
        //of what the next iteration starts with. It is not the fall-through
        //state (the body may always `return` after it), so record it on the
        //loop and report it there unconditionally.
        let scope = self.get_scope();
        let loop = self.enclosing_loop(scope);
        if(loop.is_some() && scope.id != loop.unwrap().id){
            let lp = loop.unwrap();
            for pair in &scope.state_map{
                if(!pair.b.is_moved()){
                    continue;
                }
                let vs = self.rhs_var_scope(pair.a);
                if(vs == -1 || self.scope_within(vs, lp.id)){
                    continue;
                }
                let lpst = lp.state_map.get(pair.a);
                if(lpst.is_some() && lpst.unwrap().is_moved()){
                    //moved straight-line in the body too: check_loop_moves
                    //reports the back-edge already
                    continue;
                }
                let ml = scope.line;
                if let StateType::MOVED(l)=pair.b{
                    ml = *l;
                }
                self.note_loop_jump(&lp.cont_moved, pair.a, ml);
            }
        }
        self.do_jump_drops(line);
    }
    
    func do_break(self, line: i32){
        //A `break` leaves the loop: what it moved does not reach the
        //back-edge, but the code *after* the loop must not drop it either.
        //x has no drop flags, so remember the places and let the loop's end
        //report the ambiguity (a straight-line move before the break is
        //already in the loop scope's own state and drops correctly after).
        let scope = self.get_scope();
        let loop = self.enclosing_loop(scope);
        if(loop.is_some()){
            let lp = loop.unwrap();
            if(scope.id != lp.id){
                for pair in &scope.state_map{
                    if(!pair.b.is_moved()){
                        continue;
                    }
                    let vs = self.rhs_var_scope(pair.a);
                    if(vs == -1 || self.scope_within(vs, lp.id)){
                        //temporary or loop-local: nothing is dropped after
                        continue;
                    }
                    let lpst = lp.state_map.get(pair.a);
                    if(lpst.is_some() && lpst.unwrap().is_moved()){
                        //already gone on the fall-through path too
                        continue;
                    }
                    let ml = scope.line;
                    if let StateType::MOVED(l)=pair.b{
                        ml = *l;
                    }
                    self.note_loop_jump(&lp.break_moved, pair.a, ml);
                }
            }
        }
        self.do_jump_drops(line);
    }

    func check_ptr_field(self, scope: VarScope*, line: i32){
        //Superseded by check_ptr_moves (heal-aware records): the old
        //mark-scan fired before reassignment could heal and used a
        //different message for the same rule. Kept as a no-op for the
        //move_ptr_field flag plumbing.
    }

    func end_scope(self, line: i32){
        let scope = self.get_scope();
        //assert(scope.kind is ScopeType::ELSE || scope.kind is ScopeType::IF);
        //A loop body that moves an outer drop value and can reach the
        //back-edge is a use after move on the next iteration (see
        //check_loop_moves). A body that always leaves the loop (break,
        //return, panic) is fine: the move then happens at most once.
        if(scope.kind is ScopeType::WHILE || scope.kind is ScopeType::FOR){
            if(!scope.exit.always_leaves_loop()){
                self.check_loop_moves(scope);
            }
            //A `continue` path reaches the back-edge even when the body's
            //fall-through path always leaves (a `return` after an if).
            for pm in &scope.cont_moved{
                if(scope.pre_moved.contains(&pm.key)){
                    continue;
                }
                self.get_resolver().err(pm.line, format("`{}` is moved on a path that continues the loop; the next iteration would use it after the move", pm.name));
            }
            //a place moved on a `break` path (and not on the fall-through)
            //would need a drop decision x cannot make without flags
            for pm in &scope.break_moved{
                if(scope.pre_moved.contains(&pm.key)){
                    continue;
                }
                self.get_resolver().err(pm.line, format("`{}` is moved on a path that breaks out of the loop; x cannot tell whether to drop it after the loop", pm.name));
            }
        }
        if(scope.exit.is_jump()){
            //has own drop, just update state
            self.check_ptr_moves(scope, line);
            self.end_scope_update();
            self.set_current(scope.parent);
            return;
        }
        if(verbose){
            print("end_scope {:?} sline: {} line: {}\n", scope.kind, scope.line, line);
        }
        //inspect-only match/if-let arms: bindings that never escaped
        //alias the scrutinee, so suppress them and roll the scrutinee
        //back instead of leaking it (see end_match_arm). Jump arms exit;
        //their marks stand as emitted on their own paths. Unhealed
        //pointer moves error here (see check_ptr_moves).
        if(scope.kind is ScopeType::MATCH_CASE || scope.kind is ScopeType::IF){
            self.end_match_arm(scope);
        }
        //bubble unhealed pointer moves to the parent: a heal in an outer
        //scope still counts (conditional move + outer heal). Jumps and
        //returns keep checking locally (nothing can follow them).
        self.bubble_ptr_moves(scope);
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
            }
        }
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
                continue;
            }
            let else_state = self.get_state(&rhs, else_scope);
            if(else_state.is_moved()){
                //print("sibling2 {}\n", var);
                //else moved outer, drop in if
                self.drop_var(var, if_scope, line);
                //panic("moved in sibling {}", var);
            }
        }
        //restore old scope
        for(let i = 0;i < visitor.scopes.len();++i){
            let st = visitor.scopes.get(i);
            self.scope_map.remove(st);
        }
        if(verbose){
            print("\n");
        }
        self.set_current(if_scope.parent);
    }

    //base expression of a field place, descending nested field accesses
    func place_root(self, e: Expr*): Expr*{
        if let Expr::Access(scp, name) = e{
            return self.place_root(scp.get());
        }
        return e;
    }
    //Assigning to a field of an owned temporary, `f().field = v`: the
    //temporary is registered as an object and dropped at scope end, so its
    //field is live by construction and the overwritten value must drop here
    //too -- else the old value leaks. Walks field accesses down to the base
    //expression and matches it against the registered temp objects (mirrors
    //is_temp_scrutinee's scope walk). Other untracked bases (bare
    //`ptr::deref!`, extern results) are left to the silent no-op below.
    func drop_temp_field(self, lhs: Expr*, ptr: LLVMPtr, rhs: Rhs*){
        let root = self.place_root(lhs);
        let scope = self.get_scope();
        while(true){
            for obj in &scope.objects{
                if(obj.expr.id == root.id){
                    let okey = Rhs::new(obj.expr, self);
                    if(self.get_state(&okey, scope).is_moved()){
                        return;
                    }
                    if(print_drop_lhs){
                        Logger::add(format("drop_lhs(temp field) {:?} line: {}\n", lhs, lhs.line));
                    }
                    if(drop_lhs_enabled){
                        let rt = self.get_type(lhs);
                        self.drop_force(&rt, ptr, lhs.line, rhs);
                    }
                    return;
                }
            }
            if(scope.parent == -1){
                break;
            }
            scope = self.get_scope(scope.parent);
        }
    }
    //True for `arr[i]` (a real index, not a slice `arr[a..b]` or `arr[i..]`)
    //and for a field chain rooted at one (`arr[i].f`, `arr[i].f[0]`, ...):
    //places whose base aggregate keeps every element live, so an overwrite
    //through them must drop the old value (and a move out of the *root*
    //element place must be tracked, see do_move). Bare `ptr::deref!(...)`
    //and other untracked roots are not included and stay silent no-ops, as
    //documented.
    func is_index_place(self, e: Expr*): bool{
        if let Expr::ArrAccess(aa) = e{
            return aa.idx2.is_none();
        }
        if let Expr::Access(scp, name) = e{
            return self.is_index_place(scp.get());
        }
        return false;
    }
    //The tracked element place at the root of a place expression: `arr[i]`
    //for `arr[i]`, `arr[i].f`, `arr[i].f[0]`; for `m[0][1]` it is the
    //innermost index that Rhs::new can name (`m[0]`, when the base is a
    //plain local array). None when no index level is trackable. Used to
    //consult the element's state before dropping an overwrite into it.
    func index_root(self, e: Expr*): Option<Rhs>{
        if let Expr::Access(scp, name) = e{
            return self.index_root(scp.get());
        }
        if let Expr::ArrAccess(aa) = e{
            let r = Rhs::new(e, self);
            if(r is Rhs::INDEX){
                return Option<Rhs>::new(r);
            }
            return self.index_root(aa.arr.get());
        }
        return Option<Rhs>::new();
    }
    func drop_lhs(self, lhs: Expr*, ptr: LLVMPtr){
        if(!self.is_drop_type(lhs)){
            return;
        }
        let lhs2 = Rhs::new(lhs, self);
        //A place rooted at an index (`arr[i] = v`, `arr[i].f = v`, any
        //depth): the base aggregate keeps owning every element, so the value
        //being overwritten is live and must drop here; `store` hands us its
        //address. The element is a *tracked* place when the base is a local
        //array with a constant index (Rhs::INDEX): then a moved-out element
        //is already dead, so neither it nor anything into it may drop the
        //stale value -- exactly like a moved field. For deeper shapes
        //(`arr[i].f = v`) the tracked level is the index root. (The
        //struct-field path below only sees plain FIELD shapes.)
        if(self.is_index_place(lhs)){
            let tracked = self.index_root(lhs);
            if(tracked.is_some()){
                let r = tracked.unwrap();
                let st = self.get_state(&r, self.get_scope());
                if(st.is_moved()){
                    return;
                }
            }
            if(drop_lhs_enabled){
                let rt = self.get_type(lhs);
                self.drop_force(&rt, ptr, lhs.line, &lhs2);
            }
            return;
        }
        //untracked base (field of a call result, deref of a call): no place
        //state exists. A field of an owned temporary is the one case we can
        //still own: the engine registers that temporary as an object, so the
        //field is live and the overwritten value must drop. Everything else
        //(bare `ptr::deref!`, extern results) keeps its manual drops (if
        //any) and this stays a silent no-op rather than a compiler panic.
        if(lhs2 is Rhs::EXPR){
            if(lhs is Expr::Access){
                self.drop_temp_field(lhs, ptr, &lhs2);
            }
            return;
        }
        //Unregistered named place: same robustness rule (today this only
        //happens for non-drop or global shapes, but never crash here).
        if let Rhs::VAR(v) = &lhs2{
            if(self.var_map.get(&v.id).is_none()){
                return;
            }
        }
        let state = self.get_state(&lhs2, self.get_scope());
        if(state.is_moved()){
            return;
        }
        if(print_drop_lhs){
            Logger::add(format("drop_lhs {:?} line: {}\n", lhs, lhs.line));
        }
        if(drop_lhs_enabled){
            let rt = self.get_type(lhs);
            self.drop_force(&rt, ptr, lhs.line, &lhs2);
        }
    }
}

//drop logic
impl Own{
    func check_partial(self, var: Variable*, scope: VarScope*, line: i32){
        //check if all fields moved
        //let rhs = Rhs::new(var);
        let resolver = self.get_resolver();
        let rt = resolver.visit_type(&var.type);
        //A tuple has no decl; its elements are its fields, named by index
        //(the same name Rhs::new gives `t.0`). Enumerating them used to
        //panic in get_decl. An array is the same story, but its elements are
        //Rhs::INDEX places (`arr[0]`), one per slot, all of the element type.
        let names = List<String>::new();
        let types = List<Type>::new();
        let places = List<Rhs>::new();
        if let Type::Tuple(tt) = &rt.type{
            for(let i = 0;i < tt.types.len();++i){
                names.add(format("{}", i));
                types.add(tt.types.get(i).clone());
                places.add(Rhs::new(var.clone(), names.get(i).clone()));
            }
        }else if let Type::Array(elem, size) = &rt.type{
            for(let i = 0;i < *size;++i){
                names.add(format("{}", i));
                types.add(elem.get().clone());
                places.add(Rhs::new(var.clone(), i));
            }
        }else{
            let decl = resolver.get_decl(&rt).unwrap();
            if(decl is Decl::TupleStruct){
                //positional fields: same place names Rhs::new gives `t.0`.
                let fields = decl.get_fields();
                for(let i = 0;i < fields.len();++i){
                    names.add(format("{}", i));
                    types.add(fields.get(i).type.clone());
                    places.add(Rhs::new(var.clone(), names.get(i).clone()));
                }
            }else{
                let fields = decl.get_fields();
                for fd in fields{
                    names.add(fd.name.get().clone());
                    types.add(fd.type.clone());
                    places.add(Rhs::new(var.clone(), fd.name.get().clone()));
                }
            }
        }
        let moved_fields = List<String>::new();
        for(let i = 0;i < names.len();++i){
            let rhs = places.get(i).clone();
            let state = self.get_state(&rhs, scope);
            if(state.kind is StateType::MOVED){
                moved_fields.add(names.get(i).clone());
            }else if(state.kind is StateType::MOVED_PARTIAL){
                resolver.err(var.line, "move of partial of partial");
            }
        }
        let err = false;
        for(let i = 0;i < names.len();++i){
            if(!self.is_drop_type(types.get(i))){
                continue;
            }
            if(!moved_fields.contains(names.get(i))){
                print("field '{:?}.{:?}' vline: {} not moved at: {}\n", var.name, names.get(i), var.line, line);
                err = true;
            }
        }
        if(err){
            resolver.err(line, "");
        }
    }
    func drop_var(self, var: Variable*, scope: VarScope*, line: i32){
        if(var.is_self && is_drop_method(self.method)){
            return;
        }
        if(var.is_captured){
            //a captured parameter of a generated lambda method borrows the
            //closure object's field; the object owns it and drops it when the
            //closure dies (Emitter::drop_force). Dropping here would free it
            //on every call, and the object would free it again.
            return;
        }
        if(var.type.is_pointer()){
            //use get_state for each field
            return;
        }
        let rhs = Rhs::new(var.clone());
        //explicitly dropped by hand: the manual call frees it, skip the
        //auto duplicate (see note_explicit_drop).
        let ekey = Fmt::str(&rhs);
        if(self.explicit_drops.contains(&ekey)){
            return;
        }
        let state = self.get_state(&rhs, scope);
        if(print_kind is PrintKind::Any){
            let info = scope.print_info();
            Logger::add(format("drop_var {:?} line: {} state: {:?} scope: {:?}\n", var, line,  state, info));
        }

        if(state.kind is StateType::MOVED_PARTIAL){
            self.check_partial(var, scope, line);
            //self.get_resolver().err(var.line, format("var {} moved partially", var));
            return;
        }
        if(state.is_moved()){
            return;
        }
        if(print_kind is PrintKind::Valid){
            let tmp = scope.print_info();
            Logger::add(format("drop_var_real {:?} line: {} state: {:?} scope: {:?}\n", var, line,  state, tmp));
        }
        let rt = self.get_resolver().visit_type(&var.type);
        self.drop_real(&rt, var.ptr, line, &rhs);
    }
    func drop_var_real(self, var: Variable*, line: i32){
        if(print_kind is PrintKind::Valid){
            Logger::add(format("drop_var_real {:?}\n", var));
        }
        let rt = self.get_resolver().visit_type(&var.type);
        let rhs = Rhs::new(var.clone());
        self.drop_real(&rt, var.ptr, line, &rhs);
    }
    func drop_obj(self, obj: Object*, scope: VarScope*, line: i32){
        let rhs = Rhs::new(obj.expr, self);
        //explicitly dropped by hand: skip the auto duplicate.
        let ekey = Fmt::str(&rhs);
        if(self.explicit_drops.contains(&ekey)){
            return;
        }
        let state = self.get_state(&rhs, scope);
        if(print_kind is PrintKind::Any){
            Logger::add(format("drop_obj {:?} state: {:?} oline: {} line: {}\n", obj.expr, state.kind, obj.expr.line, line));
        }
        if(state.is_moved()){
            return;
        }
        if(print_kind is PrintKind::Valid){
            Logger::add(format("drop_obj_real {:?} state: {:?} oline: {} line: {}\n", obj.expr, state.kind, obj.expr.line, line));
        }
        let resolver = self.get_resolver();
        let mut_rt = resolver.visit(obj.expr);
        //A discarded format()/`?` macro result: the macro call's own RType
        //is a bare, decl-less placeholder that drop-glue cannot resolve.
        //Use the resolved result type recorded on the block's FormatInfo.
        let info = resolver.format_map.get(&obj.expr.id);
        if(info.is_some()){
            mut_rt = info.unwrap().rt.clone();
        }
        self.drop_real(&mut_rt, obj.ptr, line, &rhs);
    }

    func drop_real(self, rt: RType*, ptr: LLVMPtr, line: i32, rhs: Rhs*){
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
    func drop_force(self, rt: RType*, ptr: LLVMPtr, line: i32, rhs: Rhs*){
        self.compiler.drop_force(rt, ptr, line, rhs);
    }
}
