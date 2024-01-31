import parser/bridge
import parser/compiler
import parser/compiler_helper
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
  func alloc_ty(self, ty: Type*, node: Fragment*): Value*{
    let mapped = self.c.mapType(ty);
    let ptr = CreateAlloca(mapped);
    self.c.allocMap.add(node.id, ptr);
    return ptr;
  }
  func alloc_ty(self, ty: Type*, node: Expr*): Value*{
    let mapped = self.c.mapType(ty);
    return self.alloc_ty(mapped, node);
  }
  func alloc_ty(self, ty: llvm_Type*, node: Expr*): Value*{
    let ptr = CreateAlloca(ty);
    self.c.allocMap.add(node.id, ptr);
    return ptr;
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
      let rhs = self.visit(&f.rhs);
      if(!doesAlloc(&f.rhs, self.c.resolver)){
        let ptr = self.alloc_ty(&ty.type, f);
        Value_setName(ptr, f.name.cstr());
      }else{
        Value_setName(rhs.unwrap(), f.name.cstr());
      }
    }
  }
  
  func visit(self, node: Expr*): Option<Value*>{
    if let Expr::Lit(kind, val*, sf*)=(node){
      if(kind is LitKind::STR){
        let st = self.c.protos.get().std("str");
        return Option::new(self.alloc_ty(st as llvm_Type*, node));
      }
      return Option<Value*>::new();
    }
    panic("alloc %s\n", node.print().cstr());
  }
}