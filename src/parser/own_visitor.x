import std/map
import std/stack

import ast/ast
import ast/printer
import ast/utils

import resolver/resolver

import parser/ownership
import parser/own_helper
import parser/own_model

struct OwnVisitor{
    own: Own*;
    if_scope: i32;
    scopes: List<i32>;//tmp scopes created, will be removed later
}

impl OwnVisitor{
    func new(own: Own*): OwnVisitor{
        return OwnVisitor{
            own: own,
            if_scope: -1,
            scopes: List<i32>::new()
        };
    }
    func get_resolver(self): Resolver*{
        return self.own.get_resolver();
    }
    func do_move(self, expr: Expr*){
        self.own.do_move(expr);
    }
    func begin(self, node: Body*): i32{
        let prev = self.own.get_scope().id;
        let id = self.own.add_scope(ScopeType::ELSE, node);
        self.scopes.add(id);
        self.visit(node);
        self.own.set_current(prev);
        return id;
    }
    func visit(self, node: Body*){
        match node{
            Body::Block(b) => {
                self.visit_block(b);
            },
            Body::Stmt(b) => {
                self.visit(b);
            },
            Body::If(b) => {
                
            },
            Body::IfLet(b) => {
                
            }
        }
    }
    func visit(self, node: Stmt*){
        match node{
            Stmt::Var(ve)=>{
                self.visit_var(ve);
            },
            Stmt::Expr(expr)=>{
                self.visit_expr(expr);
            },
            _=>{
                //panic("visit line: {} {}\n", node.line, node);
            }
        }
    }
    func visit_block(self, block: Block*){
        for(let i = 0;i < block.list.len();++i){
            let stmt = block.list.get(i);
            self.visit(stmt);
        }
    }
    func visit_var(self, ve: VarExpr*){
        for(let i = 0;i < ve.list.len();++i){
            let fr = ve.list.get(i);
            self.own.add_var(fr, LLVMPtr::new(ptr::null<Value>()));
            self.do_move(&fr.rhs);
        }
    }
    func visit_expr(self, expr: Expr*){
        match expr{
            Expr::Call(call)=>{
                self.visit_call(expr, call);
            },
            Expr::MacroCall(mc)=>{
                self.visit_macrocall(expr, mc);
            },
            Expr::Obj(type, args)=>{
                self.visit_obj(expr, type, args);
            },
            Expr::Lambda(_)=>{
                //the creation site moves the captured owners into the closure
                //object (the emitter's Expr::Lambda arm); mirror that here so
                //the else-path re-analysis sees the same marks.
                let caps = self.get_resolver().lambda_caps.get(&expr.id);
                if(caps.is_some()){
                    let list = caps.unwrap();
                    for cap in list{
                        self.do_move(cap);
                    }
                }
            },
            Expr::Infix(op, l, r)=>{
                if(op.eq("=")){
                    self.visit_expr(r.get());
                    self.own.do_assign(l.get(), r.get());
                }
            },
            _=>{}
        }
    }
    func visit_call(self, expr: Expr*, mc: Call*){
        if(Utils::is_call(mc, "std", "no_drop")){
            let arg = mc.args.get(0);
            self.do_move(arg);
            return;
        }
        //explicit drop: record the receiver so auto-drop never double-frees
        //it on any path (conditional drops included). No marks: drops destroy
        //in place, and reassignment below clears the record for the fresh
        //value. Sibling scopes snapshot clean states, so checks there are
        //unaffected. See Own::note_explicit_drop.
        if(mc.name.eq("drop") && mc.scope.is_some() && mc.args.empty()){
            self.own.note_explicit_drop(mc.scope.get());
        }
        let resolver = self.get_resolver();
        //A block the resolver recorded for this *Call* node (`format(...)`,
        //std::print_type, std::env) is what the emitter expands at the call
        //site, so walking it is what tracks moves/drops inside it. Bang forms
        //never get here: the parser makes an Expr::MacroCall for every
        //`name!(...)` (see visit_macrocall below), which is why this no longer
        //needs a macro-name test -- matching a Call's name against the unit's
        //macros was how user macro calls were *meant* to arrive, and they never
        //do.
        let finfo_opt = resolver.format_map.get(&expr.id);
        if(finfo_opt.is_some()){
            let info = finfo_opt.unwrap();
            self.visit_block(&info.block);
            if(info.block.return_expr.is_some()){
                self.do_move(info.block.return_expr.get());
            }
            return;
        }
        let rt = self.get_resolver().visit(expr);
        if(!rt.is_method()){
            //Drop::drop with no impl to resolve: a pointer/prim argument, a
            //type that needs no dropping, or an array/tuple (whose elements
            //the emitter drops in place, see Emitter::visit_call). An
            //aggregate argument is consumed here; without this mark a
            //binding it came from (an enum variant field, say) would
            //auto-drop it too -- double free.
            if(Utils::is_call(mc, "Drop", "drop")){
                self.do_move(mc.args.get(0));
            }
            //macro
            return;
        }
        let target = self.get_resolver().get_method(&rt).unwrap();
        let argIdx = 0;
        if(target.self.is_some()){
            if(mc.is_static){
                ++argIdx;
                self.do_move(mc.args.get(0));
              }else if(target.self.get().is_deref){
                self.do_move(mc.scope.get());
              }
        }
        for(;argIdx < mc.args.len();++argIdx){
            let arg = mc.args.get(argIdx);
            self.do_move(arg);
        }
        //mirror of the backend hook: else-path re-analysis must see the
        //same marks or arm merges disagree.
        self.own.consume_alias_args(mc, target, expr.line);
    }

    //Every `name!(...)` parses as an Expr::MacroCall (see the parser), so this
    //is where a macro's expansion is reached. The resolver keeps that
    //expansion in format_map keyed by the call's node id and the emitter emits
    //the block at the call site; walking it here is what mirrors the movement
    //and drops inside the expansion. The else-path re-analysis depends on it:
    //when an *else* branch moves an outer value through a macro,
    //Own::end_scope_if only drops that value on the then path because the
    //else scope records the move (before this arm existed the then path
    //silently leaked it, see tests/own/31macro_else.x).
    func visit_macrocall(self, expr: Expr*, mc: MacroCall*){
        let resolver = self.get_resolver();
        let info_opt = resolver.format_map.get(&expr.id);
        if(info_opt.is_none()){
            //a builtin with nothing recorded (ptr::deref! and friends)
            return;
        }
        let info = info_opt.unwrap();
        self.visit_block(&info.block);
        if(info.block.return_expr.is_some()){
            self.do_move(info.block.return_expr.get());
        }
    }

    func visit_obj(self, expr: Expr*, type: Type*, args: List<Entry>*){
        for(let i = 0;i < args.len();++i){
            let arg = args.get(i);
            self.do_move(&arg.expr);
        }
    }
}