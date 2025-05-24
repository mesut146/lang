import std/map
import std/stack

import parser/ast
import parser/ownership
import parser/own_helper
import parser/own_model
import parser/bridge
import parser/utils
import parser/printer
import parser/compiler
import parser/resolver
import parser/compiler_helper
import parser/debug_helper

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
            self.own.add_var(fr, ptr::null<Value>());
            self.do_move(&fr.rhs);
        }
    }
    func visit_expr(self, expr: Expr*){
        match expr{
            Expr::Call(call)=>{
                self.visit_call(expr, call);
            },
            Expr::Obj(type, args)=>{
                self.visit_obj(expr, type, args);
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
        if(Resolver::is_call(mc, "std", "no_drop")){
            let arg = mc.args.get(0);
            self.do_move(arg);
            return;
        }
        if(Resolver::is_format(mc)){
            let info = self.get_resolver().format_map.get(&expr.id).unwrap();
            self.visit_block(&info.block);
            self.do_move(info.block.return_expr.get());
            return;
        }
        let rt = self.get_resolver().visit(expr);
        if(!rt.is_method()){
            //macro
            rt.drop();
            return;
        }
        let target = self.get_resolver().get_method(&rt).unwrap();
        rt.drop();
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
    }

    func visit_obj(self, expr: Expr*, type: Type*, args: List<Entry>*){
        for(let i = 0;i < args.len();++i){
            let arg = args.get(i);
            self.do_move(&arg.expr);
        }
    }
}