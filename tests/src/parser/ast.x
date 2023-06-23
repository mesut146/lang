class Unit{
  path: String;
  last_line: i32;
  imports: List<ImportStmt>;
  items: List<Item>;
}
impl Debug for Unit{
  func debug(self, f: Fmt*){
    join(f, self.imports, "\n");
    f.print("\n");
    join(f, self.items, "\n");
  }
}

impl Unit{
  func new(path: String): Unit{
    return Unit{path.clone(), 0, List<ImportStmt>::new(), List<Item>::new()};
  }
}

class ImportStmt{
  list: List<String>;
}
impl Debug for ImportStmt{
  func debug(self, f: Fmt*){
    f.print("import ");
    join(f, self.list, "/");
  }
}

enum Item{
  Method(m: Method),
  Struct(s: StructDecl),
  Enum(ed: EnumDecl),
  Impl(i: Impl)
}

impl Debug for Item{
  func debug(self, f: Fmt*){
    if let Item::Struct(s)=(self){
      s.debug(f);
    }else if let Item::Enum(decl)=(self){
      decl.debug(f);
    }else if let Item::Method(m)=(self){
      m.debug(f);
    }else if let Item::Impl(i)=(self){
      i.debug(f);
    }else{
      panic("todo");
    }
  }
}

struct Impl{
  type_params: List<Type>;
  trait_name: Option<Type>;
  type: Type;
  methods: List<Method>;
}

func body(node: Stmt*, f: Fmt*){
  let s = Fmt::str(node); 
  let lines = s.str().split("\n");
  for(let j = 0;j < lines.len();++j){
    f.print("  ");
    f.print(lines.get(j));
    f.print("\n");
  }
}

impl Debug for Impl{
  func debug(self, f: Fmt*){
    f.print("impl ");
    if(self.trait_name.is_some()){
      self.trait_name.get().debug(f);
      f.print(" for ");
    }
    self.type.debug(f);
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

class BaseDecl{
  line: i32;
  unit: Unit*;
  type: Type;
  is_resolved: bool;
  is_generic: bool;
  base: Option<Type>;
  derives: List<Type>;
}

class StructDecl: BaseDecl{
  fields: List<FieldDecl>;
}

impl Debug for StructDecl{
  func debug(self, f: Fmt*){
    f.print("struct ");
    (self as BaseDecl*).type.debug(f);
    f.print("{\n");
    for(let i=0;i< self.fields.len();++i){
      f.print("  ");
      self.fields.get(i).debug(f);
      f.print(";\n");
    }
    f.print("}\n");
  }
}


class FieldDecl{
  name: String;
  type: Type;
}
impl Debug for FieldDecl{
  func debug(self, f: Fmt*){
    f.print(self.name);
    f.print(": ");
    self.type.debug(f);
    //f.print(";\n");
  }
}

class EnumDecl: BaseDecl{
  variants: List<Variant>;
}
impl Debug for EnumDecl {
  func debug(self, f: Fmt*){
    f.print("enum ");
    (self as BaseDecl*).type.debug(f);
    f.print("{\n");
    for(let i=0;i<self.variants.len();++i){
      let ev = self.variants.get_ptr(i);
      f.print("  ");
      f.print(ev.name);
      if(ev.fields.len()>0){
        f.print("(");
        for(let j=0;j< ev.fields.len();++j){
          if(j > 0) f.print(", ");
          ev.fields.get(j).debug(f);
        }
        f.print(")");
      }
      if(i < self.variants.len() - 1) f.print(",");
      f.print("\n");
    }
    f.print("}\n");
  }
}

class Variant{
  name: String;
  fields: List<FieldDecl>;
}

class Method{
  line: i32;
  unit: Unit*;
  type_args: List<Type>;
  name: String;
  self: Option<Param>;
  params: List<Param>;
  type: Type;
  body: Option<Block>;
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
    join(f, self.params, ", ");
    f.print("): ");
    self.type.debug(f);
    if(self.body.is_some()){
      self.body.get().debug(f);
    }else{
      f.print(";");
    }
  }
}

struct Param{
  name: String;
  type: Type;
  is_self: bool;
}

impl Debug for Param{
  func debug(self, f: Fmt*){
    f.print(self.name);
    if(self.is_self){}
    f.print(": ");
    self.type.debug(f);
  }
}

enum Type{
  Simple(scope: Option<Box<Type>>, name: String, args: List<Type>),
  Pointer(type: Box<Type>),
  Array(type: Box<Type>, size: i32),
  Slice(type: Box<Type>)
}

impl Type{
  func new(s: String): Type{
    return Type::Simple{Option<Box<Type>>::None, s, List<Type>::new()};
  }
  func new(s: String, g: List<Type>): Type{
    return Type::Simple{Option<Box<Type>>::None, s, g};
  }
  func new(scp: Type, s: String): Type{
    return Type::Simple{Option::new(Box::new(scp)), s, List<Type>::new()};
  }
  
  func name(self): String*{
    if let Type::Simple(scp, nm, args)=(self){
      return &nm;
    }
    panic("cant unwrap");
  }
  
  func print(self): String{
    return Fmt::str(self);
  }
}

impl Debug for Type{
  func debug(self, f: Fmt*){
    if let Type::Simple(scp, name, args)=(self){
      if(scp.is_some()){
        scp.get().get().debug(f);
        f.print("::");
      }
      f.print(name);
      if(!args.empty()){
        f.print("<");
        for(let i=0;i<args.len();++i){
          if(i>0) f.print(", ");
          args.get_ptr(i).debug(f);
        }
        f.print(">");
      }
    }
    else if let Type::Pointer(ty)=(self){
      ty.get().debug(f);
      f.print("*");
    }
    else if let Type::Array(box, sz)=(self){
      f.print("[");
      box.get().debug(f);
      f.print("; ");
      sz.debug(f);
      f.print("]");
    }
    else if let Type::Slice(box)=(self){
      f.print("[");
      box.get().debug(f);
      f.print("]");
    }else panic("");
  }
}

enum Stmt{
 Block(x: Block),
 Var(ve: VarExpr),
 Expr(e: Expr),
 Ret(e: Option<Expr>),
 While(e: Expr, b: Block),
 If(e: Expr, then: Box<Stmt>, els: Option<Box<Stmt>>),
 IfLet(ty: Type, args: List<String>, rhs: Expr, then: Box<Stmt>, els: Option<Box<Stmt>>),
 For(v: Option<VarExpr>, e: Option<Expr>, u: List<Expr>, s: Box<Stmt>),
 Continue,
 Break,
 Assert(e: Expr)
}

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
    else if let Stmt::If(e, then, els)=(self){
     f.print("if(");
     e.debug(f);
     f.print(")");
     if(!(then.get() is Stmt::Block)){
       f.print(" ");
     }
     then.get().debug(f);
     if(els.is_some()){
       f.print("\nelse ");
       els.get().get().debug(f);
     }
    }else if let Stmt::IfLet(ty, args, rhs, then, els)=(self){
      f.print("if let ");
      ty.debug(f);
      f.print("(");
      join(f, args, ", ");
      f.print(") = (");
      rhs.debug(f);
      f.print(")");
      then.get().debug(f);
      if(els.is_some()){
        f.print("else ");
        els.get().get().debug(f);
      }
    }else if let Stmt::For(v,e,u,b)=(self){
      f.print("for(");
      if(v.is_some()){
        v.get().debug(f);
      }
      f.print(";");
      if(e.is_some()){
        e.get().debug(f);
      }
      f.print(";");
      join(f, u, ", ");
      f.print(")");
      b.get().debug(f);
    }else if let Stmt::Continue=(self){
      f.print("continue;");
    }else if let Stmt::Break=(self){
      f.print("break;");
    }else if let Stmt::Assert(e)=(self){
      f.print("assert ");
      e.debug(f);
      f.print(";");
    }
    else{
      panic("stmt");
    }
  }
}

struct Block{
  list: List<Stmt>;
}

impl Debug for Block{
  func debug(self, f: Fmt*){
    f.print("{\n");
    for(let i=0;i<self.list.len();++i){
       body(self.list.get_ptr(i), f);
    }
    f.print("}");
  }
}

struct VarExpr{
  list: List<Fragment>;
}

impl VarExpr{
  func new(): VarExpr{
    return VarExpr{List<Fragment>::new()};
  }
}

impl Debug for VarExpr{
  func debug(self, f: Fmt*){
    for(let i=0;i<self.list.len();++i){
      self.list.get(i).debug(f);
    }
  }
}

struct Fragment{
  name: String;
  type: Option<Type>;
  rhs: Expr;
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

enum LitKind{
  INT, STR, CHAR, BOOL
}

enum Expr{
  Lit(kind: LitKind, val: String),
  Name(val: String),
  Call(scope: Option<Box<Expr>>, name: String, tp: List<Type>, args: List<Expr>),
  Par(e: Box<Expr>),
  Type(val: Type),
  Unary(op: String, e: Box<Expr>),
  Infix(op: String, l: Box<Expr>, r: Box<Expr>),
  Access(scope: Box<Expr>, name: String),
  Obj(type: Type, args: List<Entry>),
  As(e: Box<Expr>, type: Type),
  Is(e: Box<Expr>, rhs: Box<Expr>),
  Array(list: List<Expr>, size: Option<i32>),
  ArrAccess(arr: Box<Expr>, idx: Box<Expr>, idx2: Option<Box<Expr>>)
}

struct Entry{
  name: Option<String>;
  expr: Expr;
  isBase: bool;
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

func join<T>(f: Fmt*, arr: List<T>){
  for(let i=0;i<arr.len();++i){
    if(i>0) f.print(", ");
    arr.get(i).debug(f);
  }
}
func join<T>(f: Fmt*, arr: List<T>, sep: str){
  for(let i=0;i<arr.len();++i){
    if(i>0) f.print(sep);
    arr.get(i).debug(f);
  }
}

impl Debug for Expr{
  func debug(self, f: Fmt*){
    if let Expr::Lit(k, v)=(self){
      f.print(v.replace("\n", "\\n"));
    }
    else if let Expr::Name(v)=(self){
      f.print(v);
    }
    else if let Expr::Call(scp, nm, tp, args)=(self){
      if(scp.is_some()){
        let s = scp.unwrap().get();
        if let Expr::Type(t)=(s){
          t.debug(f);
          f.print("::");
        }else{
          s.debug(f);
          f.print(".");
        }
      }
      f.print(nm);
      f.print("(");
      join(f, args);
      f.print(")");
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
      join(f, args, ", ");
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
      join(f, arr, ", ");
      if(sz.is_some()){
        f.print("; ");
        sz.unwrap().debug(f);
      }
      f.print("]");
    }else if let Expr::ArrAccess(arr, idx, idx2)=(self){
      arr.get().debug(f);
      f.print("[");
      idx.get().debug(f);
      if(idx2.is_some()){
        f.print("..");
        idx2.get().get().debug(f);
      }
      f.print("]");
    }
    else{
     panic("expr %d", self.index);
    }
  }
}

func newCall(name: String, args: List<Expr>): Expr{
  return Expr::Call{Option<Box<Expr>>::None, name, List<Type>::new(), args};
}
func newCall(name: String, g: List<Type>, args: List<Expr>): Expr{
  return Expr::Call{Option<Box<Expr>>::None, name, g, args};
}
func newCall(scp: Expr, name: String, args: List<Expr>): Expr{
  return Expr::Call{Option::new(Box::new(scp)), name, List<Type>::new(), args};
}