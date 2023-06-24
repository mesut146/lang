import parser/printer

struct Unit{
  path: String;
  last_line: i32;
  imports: List<ImportStmt>;
  items: List<Item>;
}


impl Unit{
  func new(path: String): Unit{
    return Unit{path.clone(), 0, List<ImportStmt>::new(), List<Item>::new()};
  }
}

struct ImportStmt{
  list: List<String>;
}

enum Item{
  Method(m: Method),
  Struct(s: StructDecl),
  Enum(ed: EnumDecl),
  Impl(i: Impl)
}

struct Impl{
  type_params: List<Type>;
  trait_name: Option<Type>;
  type: Type;
  methods: List<Method>;
}

struct BaseDecl{
  line: i32;
  unit: Unit*;
  type: Type;
  is_resolved: bool;
  is_generic: bool;
  base: Option<Type>;
  derives: List<Type>;
}

struct StructDecl: BaseDecl{
  fields: List<FieldDecl>;
}

struct FieldDecl{
  name: String;
  type: Type;
}

struct EnumDecl: BaseDecl{
  variants: List<Variant>;
}

struct Variant{
  name: String;
  fields: List<FieldDecl>;
}

struct Method{
  line: i32;
  unit: Unit*;
  type_args: List<Type>;
  name: String;
  self: Option<Param>;
  params: List<Param>;
  type: Type;
  body: Option<Block>;
}

struct Param{
  name: String;
  type: Type;
  is_self: bool;
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

struct Block{
  list: List<Stmt>;
}


struct VarExpr{
  list: List<Fragment>;
}

impl VarExpr{
  func new(): VarExpr{
    return VarExpr{List<Fragment>::new()};
  }
}

struct Fragment{
  name: String;
  type: Option<Type>;
  rhs: Expr;
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

func newCall(name: String, args: List<Expr>): Expr{
  return Expr::Call{Option<Box<Expr>>::None, name, List<Type>::new(), args};
}
func newCall(name: String, g: List<Type>, args: List<Expr>): Expr{
  return Expr::Call{Option<Box<Expr>>::None, name, g, args};
}
func newCall(scp: Expr, name: String, args: List<Expr>): Expr{
  return Expr::Call{Option::new(Box::new(scp)), name, List<Type>::new(), args};
}