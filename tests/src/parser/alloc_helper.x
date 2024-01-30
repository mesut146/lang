import parser/bridge
import parser/compiler
import parser/ast
import parser/resolver
import std/map

struct AllocHelper{
  c: Compiler*;
}

impl AllocHelper{
  func new(c: Compiler*): AllocHelper{
    return AllocHelper{c: c};
  }
  func visit(self, node: Block*){
    for(let i=0;i<node.list.len();++i){
      let st = node.list.get_ptr(i);
      self.visit(st);
    }
  }
  func visit(self, node: Stmt*){
    if let Stmt::Var(ve*)=(node){
      self.visit(ve);
      return;
    }
    panic("alloc %s\n", node.print().cstr());
  }
  func visit(self, node: VarExpr*){
    for(let i=0;i<node.list.len();++i){
      let f = node.list.get_ptr(i);
      let ty = self.c.resolver.visit(f);
      let rhs = self.visit(&f.expr);
      //let ptr = Option<Value*>::new();
      if(!doesAlloc(&f.expr)){
        let ptr = self.alloc(ty, f);
      }
    }
  }
  
  func visit(self, node: Expr*): Option<Value*>{
    panic("alloc %s\n", node.print().cstr());
  }
}