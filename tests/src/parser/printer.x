import parser/ast

func body(node: Stmt*, f: Fmt*){
  let s = Fmt::str(node); 
  let lines = s.str().split("\n");
  for(let j = 0;j < lines.len();++j){
    f.print("  ");
    f.print(lines.get(j));
    f.print("\n");
  }
}

func join<T>(f: Fmt*, arr: List<T>*){
  for(let i=0;i<arr.len();++i){
    if(i>0) f.print(", ");
    arr.get(i).debug(f);
  }
}
func join<T>(f: Fmt*, arr: List<T>*, sep: str){
  for(let i=0;i<arr.len();++i){
    if(i>0) f.print(sep);
    arr.get(i).debug(f);
  }
}

impl Debug for Unit{
  func debug(self, f: Fmt*){
    join(f, &self.imports, "\n");
    f.print("\n");
    join(f, &self.items, "\n");
  }
}


impl Debug for ImportStmt{
  func debug(self, f: Fmt*){
    f.print("import ");
    join(f, &self.list, "/");
  }
}

impl Debug for Item{
  func debug(self, f: Fmt*){
    if let Item::Decl(decl*) = (self){
      decl.debug(f);
    }else if let Item::Method(m*) = (self){
      m.debug(f);
    }else if let Item::Impl(i) = (self){
      i.debug(f);
    }else if let Item::Type(name, rhs)=(self){
      f.print("type ");
      f.print(name);
      f.print(" = ");
      rhs.debug(f);
      f.print(";");
    }else if let Item::Trait(tr*)=(self){
      f.print("trait ");
      tr.type.debug(f);
    }else if let Item::Extern(methods*)=(self){
      f.print("extern{\n");
      join(f, methods, "\n");
      f.print("\n}");
    }else{
      panic("Item::debug()");
    }
  }
}

impl Debug for Impl{
  func debug(self, f: Fmt*){
    self.info.debug(f);
    f.print("{\n");
    for(let i=0;i<self.methods.len();++i){
      let ms = Fmt::str(self.methods.get_ptr(i));
      let lines = ms.str().split("\n");
      for(let j = 0;j < lines.len();++j){
        f.print("  ");
        f.print(lines.get(j));
        f.print("\n");
      }
    }
    f.print("\n}");
  }
}

impl Debug for ImplInfo{
  func debug(self, f: Fmt*){
    f.print("impl ");
    if(self.trait_name.is_some()){
      self.trait_name.get().debug(f);
      f.print(" for ");
    }
    self.type.debug(f);
  }
}

impl Debug for Decl{
    func debug(self, f: Fmt*){
        if let Decl::Struct(fields*) = (self){
            debug_struct(self, fields, f);
        }else if let Decl::Enum(variants*) = (self){
            debug_enum(self, variants, f);
        }
    }
    func debug_struct(decl: Decl*, fields: List<FieldDecl>*, f: Fmt*){
        f.print("struct ");
        decl.type.debug(f);
        if(decl.base.is_some()){
          f.print(": ");
          decl.base.get().debug(f);
        }
        f.print("{\n");
        for(let i = 0;i < fields.len();++i){
          f.print("  ");
          fields.get(i).debug(f);
          f.print(";\n");
        }
        f.print("}\n");
    }
    func debug_enum(decl: Decl*, variants: List<Variant>*, f: Fmt*){
        f.print("enum ");
        decl.type.debug(f);
        f.print("{\n");
        for(let i = 0;i < variants.len();++i){
          let ev = variants.get_ptr(i);
          f.print("  ");
          f.print(ev.name);
          if(ev.fields.len()>0){
            f.print("(");
            for(let j = 0;j < ev.fields.len();++j){
              if(j > 0) f.print(", ");
              ev.fields.get(j).debug(f);
            }
            f.print(")");
          }
          if(i < variants.len() - 1) f.print(",");
          f.print("\n");
        }
        f.print("}\n");
    }
}

impl Debug for FieldDecl{
  func debug(self, f: Fmt*){
    f.print(self.name);
    f.print(": ");
    self.type.debug(f);
    //f.print(";\n");
  }
}

impl Debug for Method{
  func debug(self, f: Fmt*){
    f.print("func ");
    f.print(self.name);
    f.print("(");
    if(self.self.is_some()){
      self.self.get().debug(f);
      if(!self.params.empty()){
        f.print(", ");
      }
    }
    join(f, &self.params, ", ");
    f.print("): ");
    self.type.debug(f);
    if(self.body.is_some()){
      self.body.get().debug(f);
    }else{
      f.print(";");
    }
  }
}

impl Debug for Param{
  func debug(self, f: Fmt*){
    f.print(self.name);
    if(self.is_self){}
    f.print(": ");
    self.type.debug(f);
  }
}

impl Debug for Type{
  func debug(self, f: Fmt*){
    if let Type::Simple(smp*)=(self){
      if(smp.scope.is_some()){
        smp.scope.get().debug(f);
        f.print("::");
      }
      f.print(smp.name);
      if(!smp.args.empty()){
        f.print("<");
        for(let i = 0;i < smp.args.len();++i){
          if(i>0) f.print(", ");
          smp.args.get_ptr(i).debug(f);
        }
        f.print(">");
      }
    }
    else if let Type::Pointer(ty*) = (self){
      ty.get().debug(f);
      f.print("*");
    }
    else if let Type::Array(box*, sz) = (self){
      f.print("[");
      box.get().debug(f);
      f.print("; ");
      sz.debug(f);
      f.print("]");
    }
    else if let Type::Slice(box*) = (self){
      f.print("[");
      box.get().debug(f);
      f.print("]");
    }else panic("Type::debug %p", self);
  }
}

//statements------------------------------------------------
impl Debug for Stmt{
  func debug(self, f: Fmt*){
    if let Stmt::Block(b)=(self){
      b.debug(f);
    }
    else if let Stmt::Var(ve)=(self){
      f.print("let ");
      ve.debug(f);
      f.print(";");
    }else if let Stmt::Expr(e) =(self){
      e.debug(f);
      f.print(";");
    }else if let Stmt::Ret(e) =(self){
      f.print("return");
      if(e.is_some()){
        f.print(" ");
        e.unwrap().debug(f);
      }
      f.print(";");
    }else if let Stmt::While(e, b)=(self){
     f.print("while(");
     e.debug(f);
     f.print(")");
     b.debug(f);
    }
    else if let Stmt::If(is*)=(self){
     f.print("if(");
     is.e.debug(f);
     f.print(")");
     if(!(is.then.get() is Stmt::Block)){
       f.print(" ");
     }
     is.then.get().debug(f);
     if(is.els.is_some()){
       f.print("\nelse ");
       is.els.get().get().debug(f);
     }
    }else if let Stmt::IfLet(il*)=(self){
      f.print("if let ");
      il.ty.debug(f);
      f.print("(");
      join(f, &il.args, ", ");
      f.print(") = (");
      il.rhs.debug(f);
      f.print(")");
      il.then.get().debug(f);
      if(il.els.is_some()){
        f.print("else ");
        il.els.get().get().debug(f);
      }
    }else if let Stmt::For(fs*)=(self){
      f.print("for(");
      if(fs.v.is_some()){
        fs.v.get().debug(f);
      }
      f.print(";");
      if(fs.e.is_some()){
        fs.e.get().debug(f);
      }
      f.print(";");
      join(f, &fs.u, ", ");
      f.print(")");
      fs.body.get().debug(f);
    }else if let Stmt::Continue = (self){
      f.print("continue;");
    }else if let Stmt::Break = (self){
      f.print("break;");
    }else if let Stmt::Assert(e) = (self){
      f.print("assert ");
      e.debug(f);
      f.print(";");
    }
    else{
      panic("Stmt::debug");
    }
  }
}

impl Debug for ArgBind{
  func debug(self, f: Fmt*){
    f.print(self.name);
    if(self.is_ptr){
      f.print("*");
    }
  }
}

impl Debug for Block{
  func debug(self, f: Fmt*){
    f.print("{\n");
    for(let i = 0;i < self.list.len();++i){
       body(self.list.get_ptr(i), f);
    }
    f.print("}");
  }
}

impl Debug for VarExpr{
  func debug(self, f: Fmt*){
    for(let i=0;i<self.list.len();++i){
      self.list.get(i).debug(f);
    }
  }
}

impl Debug for Fragment{
  func debug(self, f: Fmt*){
    f.print(self.name);
    if(self.type.is_some()){
      f.print(": ");
      self.type.unwrap().debug(f);
    }
    f.print(" = ");
    self.rhs.debug(f);
  }
}

//expr---------------------------------
impl Debug for Expr{
  func debug(self, f: Fmt*){
    if let Expr::Lit(lit*)=(self){
      f.print(lit.val.replace("\n", "\\n"));
      if(lit.suffix.is_some()){
        f.print("_");
        lit.suffix.get().debug(f);
      }
    }
    else if let Expr::Name(v)=(self){
      f.print(v);
    }
    else if let Expr::Call(call)=(self){
      call.debug(f);
    }else if let Expr::Par(e)=(self){
      f.print("(");
      e.get().debug(f);
      f.print(")");
    }
    else if let Expr::Type(t)=(self){
      t.debug(f);
    }else if let Expr::Unary(op, e)=(self){
      f.print(op);
      e.get().debug(f);
    }
    else if let Expr::Infix(op, l, r)=(self){
      l.get().debug(f);
      f.print(" ");
      f.print(op);
      f.print(" ");
      r.get().debug(f);
    }else if let Expr::Access(scp, nm)=(self){
      scp.get().debug(f);
      f.print(".");
      f.print(nm);
    }else if let Expr::Obj(ty, args)=(self){
      ty.debug(f);
      f.print("{");
      join(f, &args, ", ");
      f.print("}");
    }else if let Expr::As(e, type)=(self){
      e.get().debug(f);
      f.print(" as ");
      type.debug(f);
    }else if let Expr::Is(e, rhs)=(self){
      e.get().debug(f);
      f.print(" is ");
      rhs.get().debug(f);
    }else if let Expr::Array(arr, sz)=(self){
      f.print("[");
      join(f, &arr, ", ");
      if(sz.is_some()){
        f.print("; ");
        sz.get().debug(f);
      }
      f.print("]");
    }else if let Expr::ArrAccess(aa*)=(self){
      aa.arr.get().debug(f);
      f.print("[");
      aa.idx.get().debug(f);
      if(aa.idx2.is_some()){
        f.print("..");
        aa.idx2.get().get().debug(f);
      }
      f.print("]");
    }
    else{
     panic("Expr::debug");
    }
  }
}

impl Debug for Call{
  func debug(self, f: Fmt*){
    if(self.scope.is_some()){
      let s = self.scope.unwrap().get();
      if let Expr::Type(t)=(s){
        t.debug(f);
        f.print("::");
      }else{
        s.debug(f);
        f.print(".");
      }
    }
    f.print(self.name);
    f.print("(");
    join(f, &self.args);
    f.print(")");
  }
}

impl Debug for Entry{
  func debug(self, f: Fmt*){
    if(self.isBase){
      f.print(".");
    }else{
    if(self.name.is_some()){
      self.name.get().debug(f);
      f.print(": ");
    }
    }
    self.expr.debug(f);
  }
}