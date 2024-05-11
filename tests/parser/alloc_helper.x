import parser/bridge
import parser/compiler
import parser/compiler_helper
import parser/ast
import parser/resolver
import parser/method_resolver
import parser/utils
import parser/debug_helper
import parser/printer
import std/map
import std/libc

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
  func alloc_ty(self, ty: Type*, node: Node*): Value*{
    let mapped = self.c.mapType(ty);
    let ptr = CreateAlloca(mapped);
    self.c.allocMap.add(node.id, ptr);
    return ptr;
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
    if let Stmt::Block(bs*)=(node){
      self.visit(bs);
      return;
    }
    if let Stmt::For(fs*)=(node){
      if(fs.v.is_some()){
        self.visit(fs.v.get());
      }
      self.visit(fs.body.get());
      return;
    }
    if let Stmt::While(e*, b*)=(node){
      self.visit(e);
      self.visit(b);
      return;
    }
    if let Stmt::If(is*)=(node){
      self.visit(&is.e);
      self.visit(is.then.get());
      if(is.els.is_some()){
        self.visit(is.els.get().get());
      }
      return;
    }
    if let Stmt::IfLet(is*)=(node){
      for(let i=0;i<is.args.len();++i){
        let arg = is.args.get_ptr(i);
        let ty = self.c.resolver.cache.get(arg.id);
        let arg_ptr = self.alloc_ty(&ty.unwrap().type, arg as Node*);
        let arg_cloned = arg.name.clone();
        Value_setName(arg_ptr, arg_cloned.clone().cstr().ptr());
        self.c.NamedValues.add(arg_cloned, arg_ptr);
      }
      self.visit(&is.rhs);
      self.visit(is.then.get());
      if(is.els.is_some()){
        self.visit(is.els.get().get());
      }
      return;
    }
    if let Stmt::Ret(e*)=(node){
      if(e.is_some()){
        self.visit_ret(node, e.get());
      }
      return;
    }
    if let Stmt::Expr(e*)=(node){
      self.visit(e);
      return;
    }
    if let Stmt::Break=(node){
      return;
    }
    if let Stmt::Continue=(node){
      return;
    }
    if let Stmt::Assert(e*)=(node){
      self.visit(e);
      return;
    }
    panic("alloc {}\n", node);
  }
  func visit_ret(self, stmt: Stmt*, expr: Expr*){
    self.visit(expr);
  }
  func visit(self, node: VarExpr*){
    for(let i=0;i<node.list.len();++i){
      let f = node.list.get_ptr(i);
      let ty = self.c.resolver.visit(f);
      let rhs: Option<Value*> = self.visit(&f.rhs);
      let name: String = f.name.clone();
      if(!doesAlloc(&f.rhs, self.c.resolver)){
        let ptr = self.alloc_ty(&ty.type, f);
        Value_setName(ptr, name.clone().cstr().ptr());
        self.c.NamedValues.add(name, ptr);
      }else{
        Value_setName(rhs.unwrap(), name.clone().cstr().ptr());
        self.c.NamedValues.add(name, rhs.unwrap());
      }
    }
  }
  
  func visit(self, node: Expr*): Option<Value*>{
    let res = Option<Value*>::new();
    if let Expr::Type(ty*)=(node){
      if(ty.is_simple()){
        let smp = ty.as_simple();
        if(smp.scope.is_some()){
          //enum creation
          return Option::new(self.alloc_ty(ty, node));
        }
      }
      return res;
    }
    if let Expr::Lit(lit*)=(node){
      if(lit.kind is LitKind::STR){
        let st = self.c.protos.get().std("str");
        return Option::new(self.alloc_ty(st as llvm_Type*, node));
      }
      return res;
    }
    if let Expr::Infix(op*, l*, r*)=(node){
      self.visit(l.get());
      self.visit(r.get());
      return res;
    }
    if let Expr::Unary(op*, e*)=(node){
      self.visit(e.get());
      return res;
    }
    if let Expr::ArrAccess(aa*)=(node){
      self.visit(aa.arr.get());
      self.visit(aa.idx.get());
      if(aa.idx2.is_some()){
        self.visit(aa.idx2.get().get());
        let st = self.c.protos.get().std("slice");
        return Option::new(self.alloc_ty(st as llvm_Type*, node));
      }
      return res;
    }
    if let Expr::Access(scope*,name*)=(node){
      self.visit(scope.get());
      return res;
    }
    if let Expr::Name(name*)=(node){
      return res;
    }
    if let Expr::Call(call*)=(node){
      let rt = self.c.resolver.visit(node);
      if(rt.method.is_some()){
        let rval = RvalueHelper::need_alloc(call, *rt.method.get(), self.c.resolver);
        if (rval.rvalue) {
            self.alloc_ty(rval.scope_type.get(), *rval.scope.get());
        }
        Drop::drop(rval);
      }
      if(rt.method.is_some() && is_struct(&rt.type)){
        //non-internal method
        res = Option::new(self.alloc_ty(&rt.type, node));
      }
      if(call.scope.is_some()){
        self.visit(call.scope.get().get());
      }
      let print_panic = call.scope.is_none() && (call.name.eq("print") || call.name.eq("panic"));
      for(let i=0;i<call.args.len();++i){
        let arg = call.args.get_ptr(i);
        if(print_panic && is_str_lit(arg).is_some()) continue;//already cstr, no need to alloc
        self.visit(arg);
      }
      return res;
    }
    if let Expr::Obj(type*, args*)=(node){
      //get full type
      let rt = self.c.resolver.visit(node);
      res = Option::new(self.alloc_ty(&rt.type, node));
      for(let i=0;i<args.len();++i){
        let arg = args.get_ptr(i);
        //self.child(&arg.expr);//rvo opt
        self.visit(&arg.expr);
      }
      return res;
    }
    if let Expr::As(e*, type*)=(node){
      self.visit(e.get());
      return res;
    }
    if let Expr::Is(e*, rhs*)=(node){
      self.visit(e.get());
      return res;
    }
    if let Expr::Par(e*)=(node){
      return self.visit(e.get());
    }
    if let Expr::Array(list*,sz*)=(node){
      let rt = self.c.resolver.visit(node);
      res = Option::new(self.alloc_ty(&rt.type, node));
      if(sz.is_some()){
        let elem = list.get_ptr(0);
        self.visit(elem);
      }else{
        for(let i=0;i<list.len();++i){
          let elem = list.get_ptr(i);
          self.visit(elem);
        }
      }
      return res;
    }
    panic("alloc {}\n", node);
  }

  func child(self, node: Expr*){

  }
}