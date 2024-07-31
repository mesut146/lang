import parser/bridge
import parser/compiler
import parser/compiler_helper
import parser/ast
import parser/resolver
import parser/method_resolver
import parser/utils
import parser/debug_helper
import parser/printer
import parser/ownership
import std/map
import std/libc
import std/stack

struct AllocHelper{
  c: Compiler*;
}

impl AllocHelper{
  func makeLocals(c: Compiler*, b: Block*){
    //allocMap.clear();
    let ah = AllocHelper::new(c);
    ah.visit(b);
  } 

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
    for(let i = 0;i < node.list.len();++i){
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
      if(fs.var_decl.is_some()){
        self.visit(fs.var_decl.get());
      }
      self.visit(fs.body.get());
      return;
    }
    if let Stmt::While(e*, b*)=(node){
      self.visit(e);
      self.visit(b.get());
      return;
    }
    if let Stmt::If(is*)=(node){
      self.visit(&is.cond);
      self.visit(is.then.get());
      if(is.else_stmt.is_some()){
        self.visit(is.else_stmt.get());
      }
      return;
    }
    if let Stmt::IfLet(is*)=(node){
      for(let i = 0;i < is.args.len();++i){
        let arg = is.args.get_ptr(i);
        let ty = self.c.get_resolver().cache.get_ptr(&arg.id);
        let arg_ptr = self.alloc_ty(&ty.unwrap().type, arg as Node*);
        let name_c = arg.name.clone().cstr();
        Value_setName(arg_ptr, name_c.ptr());
        name_c.drop();
        self.c.allocMap.add(arg.id, arg_ptr);
      }
      self.visit(&is.rhs);
      self.visit(is.then.get());
      if(is.else_stmt.is_some()){
        self.visit(is.else_stmt.get());
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
    panic("alloc {}\n", node);
  }
  func visit_ret(self, stmt: Stmt*, expr: Expr*){
    self.visit(expr);
  }
  func visit(self, node: VarExpr*){
    for(let i = 0;i < node.list.len();++i){
      let f = node.list.get_ptr(i);
      let rt = self.c.get_resolver().visit(f);
      let ptr = self.alloc_ty(&rt.type, f);
      let name_c = f.name.clone().cstr();
      Value_setName(ptr, name_c.ptr());
      name_c.drop();
      rt.drop();
      let rhs: Option<Value*> = self.visit(&f.rhs);
    }
  }

  func visit_call(self, node: Expr*, call: Call*): Option<Value*>{
    let resolver = self.c.get_resolver();
    if(Resolver::is_call(call, "std", "env")){
      let info = self.c.get_resolver().format_map.get_ptr(&node.id).unwrap();
      let rt = resolver.visit(node);
      self.visit(info.unwrap_mc.get());
      let res = Option::new(self.alloc_ty(&rt.type, node));
      rt.drop();
      return res;
    }
    if(Resolver::is_print(call) || Resolver::is_panic(call)){
      if(call.args.len() == 1){
        //simple, no alloc
      }
      let info = self.c.get_resolver().format_map.get_ptr(&node.id).unwrap();
      self.visit(&info.block);
      return Option<Value*>::new();
    }
    if(Resolver::is_assert(call)){
      let info = self.c.get_resolver().format_map.get_ptr(&node.id).unwrap();
      self.visit(&info.block);
      return Option<Value*>::new();
    }
    if(Resolver::is_format(call)){
      let info = self.c.get_resolver().format_map.get_ptr(&node.id).unwrap();
      self.visit(&info.block);
      let str_ty = Type::new("String");
      let res = Option::new(self.alloc_ty(&str_ty, info.unwrap_mc.get()));
      str_ty.drop();
      return res;
    }
    let rt = self.c.get_resolver().visit(node);
    if(rt.is_method()){
      let rt_method = self.c.get_resolver().get_method(&rt);
      let rval = RvalueHelper::need_alloc(call, rt_method.unwrap(), self.c.get_resolver());
      if (rval.rvalue) {
          self.alloc_ty(rval.scope_type.get(), *rval.scope.get());
      }
      Drop::drop(rval);
    }
    let res = Option<Value*>::new();
    if(rt.is_method() && is_struct(&rt.type)){
      //non-internal method
      res = Option::new(self.alloc_ty(&rt.type, node));
    }
    rt.drop();
    if(call.scope.is_some()){
      self.visit(call.scope.get());
    }
    for(let i = 0;i < call.args.len();++i){
      let arg = call.args.get_ptr(i);
      self.visit(arg);
    }
    return res;
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
      if(op.eq("&")){
        if(RvalueHelper::is_rvalue(e.get())){
          let ty = self.c.get_resolver().getType(e.get());
          self.alloc_ty(&ty, node);
          ty.drop();
        }
      }
      return res;
    }
    if let Expr::ArrAccess(aa*)=(node){
      self.visit(aa.arr.get());
      self.visit(aa.idx.get());
      if(aa.idx2.is_some()){
        self.visit(aa.idx2.get());
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
      return self.visit_call(node, call);
    }
    if let Expr::Obj(type*, args*)=(node){
      //get full type
      let rt = self.c.get_resolver().visit(node);
      res = Option::new(self.alloc_ty(&rt.type, node));
      rt.drop();
      for(let i = 0;i < args.len();++i){
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
      let rt = self.c.get_resolver().visit(node);
      res = Option::new(self.alloc_ty(&rt.type, node));
      rt.drop();
      if(sz.is_some()){
        let elem = list.get_ptr(0);
        self.visit(elem);
      }else{
        for(let i = 0;i < list.len();++i){
          let elem = list.get_ptr(i);
          self.visit(elem);
        }
      }
      return res;
    }
    panic("alloc {}\n", node);
  }
}