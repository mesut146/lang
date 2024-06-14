import parser/ast
import parser/ownership
import parser/bridge
import parser/utils
import parser/printer
import std/map

struct OwnVisitor{
    own: Own*;
    if_scope: i32;
}

impl OwnVisitor{
    func visit(self, node: Stmt*){
        if let Stmt::Block(b*)=(node){
            self.visit_block(b);
        }else if let Stmt::Var(ve*)=(node){
            self.visit_var(ve);
        }else if let Stmt::Expr(expr*)=(node){
            self.visit_expr(expr);
        }else{
            //panic("visit line: {} {}\n", node.line, node);
        }
    }
    func visit_block(self, block: Block*){
        for(let i = 0;i < block.list.len();++i){
            let stmt = block.list.get_ptr(i);
            self.visit(stmt);
        }
    }
    func visit_var(self, var: VarExpr*){
    }
    func visit_expr(self, expr: Expr*){
    }
}