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
import parser/own_model
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
  func check_type(ty: Type*){
    if(ty.is_void()){
      panic("internal err: alloc of void");
    }
  }
  func alloc_ty(self, ty: Type*, node: Node*): Value*{
    check_type(ty);
    let mapped = self.c.mapType(ty);
    if(ty.is_fpointer()){
      mapped = getPointerTo(getInt(8)) as llvm_Type*;
    }
    let ptr = CreateAlloca(mapped);
    self.c.allocMap.add(node.id, ptr);
    return ptr;
  }
  func alloc_ty(self, ty: Type*, node: Fragment*): Value*{
    return self.alloc_ty(ty, node as Node*);
  }
  func alloc_ty(self, ty: Type*, node: Expr*): Value*{
    return self.alloc_ty(ty, node as Node*);
  }

  func visit(self, node: Block*): Option<Value*>{
    for st in &node.list{
      self.visit(st);
    }
    if(node.return_expr.is_some()){
      return self.visit(node.return_expr.get());
    }
    return Option<Value*>::new();
  }
  func visit_body(self, body: Body*): Option<Value*>{
    match body{
        Body::Block(b*)=>{
            return self.visit(b);
        },
        Body::Stmt(b*)=>{
            self.visit(b);
            return Option<Value*>::new();
        },
        Body::If(b*)=>{
            return self.visit_if(b);
        },
        Body::IfLet(b*)=>{
            return self.visit_iflet(b);
        }
    }
  }
  func visit_if(self, node: IfStmt*): Option<Value*>{
    //todo ret value?
    self.visit(&node.cond);
    self.visit_body(node.then.get());
    if(node.else_stmt.is_some()){
      self.visit_body(node.else_stmt.get());
    }
    return Option<Value*>::new();
  }
  func visit_iflet(self, node: IfLet*): Option<Value*>{
    for arg in &node.args{
      let ty = self.c.get_resolver().cache.get(&arg.id);
      let arg_ptr = self.alloc_ty(&ty.unwrap().type, arg as Node*);
      let name_c = arg.name.clone().cstr();
      Value_setName(arg_ptr, name_c.ptr());
      name_c.drop();
      self.c.allocMap.add(arg.id, arg_ptr);
    }
    self.visit(&node.rhs);
    self.visit_body(node.then.get());
    if(node.else_stmt.is_some()){
      self.visit_body(node.else_stmt.get());
    }
    return Option<Value*>::new();
  }
  func visit(self, node: Stmt*){
      match node{
          Stmt::Var(ve*)=>{
              self.visit(ve);
              return;
          },
          Stmt::For(fs*)=>{
              if(fs.var_decl.is_some()){
                  self.visit(fs.var_decl.get());
              }
              self.visit_body(fs.body.get());
              return;
          },
          Stmt::ForEach(fe*)=>{
              let info = self.c.get_resolver().format_map.get(&node.id).unwrap();
              self.visit(&info.block);
              return;
          },
    Stmt::While(e*, b*)=>{
      self.visit(e);
      self.visit_body(b.get());
      return;
    },
    Stmt::Ret(e*)=>{
      if(e.is_some()){
        self.visit_ret(node, e.get());
      }
      return;
    },
    Stmt::Expr(e*)=>{
      self.visit(e);
      return;
    },
    Stmt::Break=>{
      return;
    },
    Stmt::Continue=>{
      return;
    },
    _=>panic("alloc {:?}\n", node)
    }
  }
  func visit_ret(self, stmt: Stmt*, expr: Expr*){
    self.visit(expr);
  }
  func visit(self, node: VarExpr*){
    for f in &node.list{
      let rt = self.c.get_resolver().visit_frag(f);
      let ptr = self.alloc_ty(&rt.type, f);
      let name_c = f.name.clone().cstr();
      Value_setName(ptr, name_c.ptr());
      name_c.drop();
      rt.drop();
      let rhs: Option<Value*> = self.visit(&f.rhs);
    }
  }
  
  func visit_mcall(self, node: Expr*, call: MacroCall*): Option<Value*>{
      let resolver = self.c.get_resolver();
      let info = resolver.get_macro(node);
      let rt = resolver.visit(node);
      self.visit(&info.block);
      if(rt.type.is_void()){
          rt.drop();
          return Option<Value*>::new();
      }
      let res = Option::new(self.alloc_ty(&rt.type, node));
      rt.drop();
      return res;
  }

  func visit_call(self, node: Expr*, call: Call*): Option<Value*>{
    let resolver = self.c.get_resolver();
    if(Resolver::is_call(call, "std", "internal_block")){
      let arg = call.args.get_ptr(0).print();
      let id = i32::parse(arg.str());
      let blk: Block* = *resolver.block_map.get(&id).unwrap();
      self.visit(blk);
      arg.drop();
      return Option<Value*>::new();
    }
    if(Resolver::is_printf(call)){
      for(let i = 1;i < call.args.len();++i){
        let arg = call.args.get_ptr(i);
        self.visit(arg);
      }
      return Option<Value*>::new();
    }
    if(Resolver::is_call(call, "std", "typeof")){
      let rt = resolver.visit(node);
      let res = Option::new(self.alloc_ty(&rt.type, node));
      rt.drop();
      return res;
    }
    if(Resolver::is_call(call, "std", "print_type")){
      let info = resolver.get_macro(node);
      let rt = resolver.visit(node);
      self.visit(info.unwrap_mc.get());
      let res = Option::new(self.alloc_ty(&rt.type, node));
      rt.drop();
      return res;
    }
    if(Resolver::is_call(call, "std", "env")){
      let info = resolver.get_macro(node);
      let rt = resolver.visit(node);
      self.visit(info.unwrap_mc.get());
      let res = Option::new(self.alloc_ty(&rt.type, node));
      rt.drop();
      return res;
    }
    if(Resolver::is_print(call) || Resolver::is_panic(call)){
      let info = resolver.get_macro(node);
      self.visit(&info.block);
      return Option<Value*>::new();
    }
    if(Resolver::is_assert(call)){
      let info = resolver.get_macro(node);
      self.visit(&info.block);
      return Option<Value*>::new();
    }
    if(Resolver::is_format(call)){
      let info = resolver.get_macro(node);
      self.visit(&info.block);
      let str_ty = Type::new("String");
      let res = Option::new(self.alloc_ty(&str_ty, info.unwrap_mc.get()));
      str_ty.drop();
      return res;
    }
    let rt = resolver.visit(node);
    if(rt.is_method()){
      let rt_method = resolver.get_method(&rt);
      let rval = RvalueHelper::need_alloc(call, rt_method.unwrap(), resolver);
      if (rval.rvalue) {
          self.alloc_ty(rval.scope_type.get(), *rval.scope.get());
      }
      rval.drop();
    }
    let res = Option<Value*>::new();
    if(rt.is_method() && is_struct(&rt.type)){
      //non-internal method
      res = Option::new(self.alloc_ty(&rt.type, node));
    }
    if(call.scope.is_some()){
      self.visit(call.scope.get());
    }
    for arg in &call.args{
      self.visit(arg);
    }
    rt.drop();
    return res;
  }
  
  func visit(self, node: Expr*): Option<Value*>{
    let res = Option<Value*>::new();
    if let Expr::Block(blk*)=(node){
      return self.visit(blk.get());
    }
    if let Expr::If(is*)=(node){
      return self.visit_if(is.get());
    }
    if let Expr::IfLet(is*)=(node){
      return self.visit_iflet(is.get());
    }
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
        let ty = Type::new("str");
        res.set(self.alloc_ty(&ty, node));
        ty.drop();
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
        let ty = self.c.get_resolver().getType(node);
        res.set(self.alloc_ty(&ty, node));
        ty.drop();
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
    if let Expr::MacroCall(call*)=(node){
      return self.visit_mcall(node, call);
    }
    if let Expr::Obj(type*, args*)=(node){
      //get full type
      let rt = self.c.get_resolver().visit(node);
      res = Option::new(self.alloc_ty(&rt.type, node));
      rt.drop();
      for arg in args{
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
        for elem in list{
          self.visit(elem);
        }
      }
      return res;
    }
    if let Expr::Match(me*)=(node){
      let rt = self.c.get_resolver().visit(node);
      if(!rt.type.is_void()){
        res = Option::new(self.alloc_ty(&rt.type, node));
      }
      self.visit(&me.get().expr);
      for case in &me.get().cases{
        if let MatchLhs::ENUM(type*, args*)=(&case.lhs){
          for arg in args{
            let ty = self.c.get_resolver().cache.get(&arg.id);
            let arg_ptr = self.alloc_ty(&ty.unwrap().type, arg as Node*);
            let name_c = arg.name.clone().cstr();
            Value_setName(arg_ptr, name_c.ptr());
            name_c.drop();
            self.c.allocMap.add(arg.id, arg_ptr);
          }
        }
        match &case.rhs{
            MatchRhs::EXPR(e*)=>{
          self.visit(e);
        },
        MatchRhs::STMT(st*)=>{
          self.visit(st);
        }
        }
      }
      rt.drop();
      return res;
    }
    if let Expr::Lambda(le*)=(node){
        let r = self.c.get_resolver();
        let m = r.lambdas.get(&node.id).unwrap();
        let ty = r.getType(node);
        res.set(self.alloc_ty(&ty, node));
        return res;
    }
    panic("alloc {:?}\n", node);
  }
}

impl AllocHelper{
  func visit_child(self, node: Expr*){
    if let Expr::Array(list*,sz*)=(node){
      if(sz.is_some()){
        let elem = list.get_ptr(0);
        self.visit(elem);
      }else{
        for elem in list{
          self.visit(elem);
        }
      }
      return;
    }else{
      panic("visit_child {:?}", node);
    }
  }
}