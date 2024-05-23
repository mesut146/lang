import std/map
import std/libc
import parser/copier
import parser/printer

func prim_size(s: str): Option<u32>{
  let prims = ["bool", "i8", "i16", "i32", "i64","u8","u16","u32","u64","f32","f64"];
  let sizes = [8,8,16,32,64, 8,16,32,64,32,64];
  for(let i = 0;i < prims.len();++i){
    if(prims[i].eq(s)){
      return Option::new(sizes[i] as u32);
    }
  }
  return Option<u32>::None;
}

func prim_size(s: String): Option<u32>{
  let res = prim_size(s.str());
  Drop::drop(s);
  return res;
}

struct Node{
  line: i32;
  pos: i32;
  id: i32;
}
impl Node{
  func new(id: i32): Node{
    return Node{line: 0, pos: 0, id: id};
  }
  func new(id: i32, line: i32): Node{
    return Node{line: line, pos: 0, id: id};
  }
}


struct Unit{
  path: String;
  last_line: i32;
  imports: List<ImportStmt>;
  items: List<Item>;
  globals: List<Global>;
  last_id: i32;
}
impl Unit{
  func new(path: String): Unit{
    return Unit{path: path,
                last_line: 0,
                imports: List<ImportStmt>::new(),
                items: List<Item>::new(),
                globals: List<Global>::new(),
                last_id: -1};
  }

  func node(self, line: i32): Node{
    let id = ++self.last_id;
    return Node::new(id, line);
  }
}

struct Global{
  name: String;
  type: Option<Type>;
  expr: Expr;
}

struct ImportStmt{
  list: List<String>;
}

impl Clone for ImportStmt{
  func clone(self): ImportStmt{
    return ImportStmt{list: self.list.clone()};
  }
}

impl ImportStmt{
  func new(): ImportStmt{
    return ImportStmt{list: List<String>::new()};
  }
}

enum Item{
  Method(m: Method),
  Decl(decl: Decl),
  Impl(i: Impl),
  Trait(t: Trait),
  Type(name: String, rhs: Type),
  Extern(methods: List<Method>)
}

impl Item{
  func as_impl(self): Impl*{
    if let Item::Impl(imp*)=(self){
      return imp;
    }
    panic("Item::as_impl()");
  }
}

struct Impl{
  info: ImplInfo;
  methods: List<Method>;
}

struct ImplInfo{
  type_params: List<Type>;
  trait_name: Option<Type>;
  type: Type;
}
impl ImplInfo{
  func new(type: Type): ImplInfo{
    return ImplInfo{List<Type>::new(), Option<Type>::None, type};
  }
  func clone(self): ImplInfo{
    return ImplInfo{self.type_params.clone(), self.trait_name.clone(), self.type.clone()};
  }
}

struct BaseDecl{
  line: i32;
  path: String;
  type: Type;
  is_resolved: bool;
  is_generic: bool;
  base: Option<Type>;
  derives: List<Type>;
  attr: List<String>;
}

enum Decl: BaseDecl{
  Struct(fields: List<FieldDecl>),
  Enum(variants: List<Variant>)
}

impl Decl{
  func is_drop(self): bool{
    for(let i = 0;i < self.attr.len();++i){
      let at = self.attr.get_ptr(i);
      if(at.eq("drop")){
        return true;
      }
    }
    return false;
  }
  func is_struct(self): bool{
    return self is Decl::Struct;
  }
  func is_enum(self): bool{
    return self is Decl::Enum;
  }
  func get_variants(self): List<Variant>*{
    if let Decl::Enum(variants*)=(self){
      return variants;
    }
    panic("get_variants {}", self.type);
  }
  func get_fields(self): List<FieldDecl>*{
    if let Decl::Struct(fields*)=(self){
      return fields;
    }
    panic("get_fields");
  }
}


struct FieldDecl{
  name: String;
  type: Type;
}


struct Variant{
  name: String;
  fields: List<FieldDecl>;
}


struct Trait{
  type: Type;
  methods: List<Method>;
}

#derive(Debug)
enum Parent{
  None,
  Impl(info: ImplInfo),
  Trait(type: Type),
  Extern
}

impl Parent{
  func is_none(self): bool{
    return self is Parent::None;
  }
  func is_impl(self): bool{
    return self is Parent::Impl;
  }
  func as_impl(self): ImplInfo*{
    if let Parent::Impl(info*)=(self){
      return info;
    }
    panic("as_impl");
  }
  func get_type(self): Type*{
    if let Parent::Trait(type*)=(self){
      return type;
    }
    if let Parent::Impl(info*)=(self){
      return &info.type;
    }
    panic("get_type");
  }
  func clone(self): Parent{
    if let Parent::None=(self){
      return Parent::None;
    }
    if let Parent::Impl(info*)=(self){
      return Parent::Impl{info.clone()};
    }
    if let Parent::Trait(type*)=(self){
      return Parent::Trait{type.clone()};
    }
    if let Parent::Extern=(self){
      return Parent::Extern;
    }
    panic("Parent::clone");
  }
}

struct Method: Node{
  type_params: List<Type>;
  name: String;
  self: Option<Param>;
  params: List<Param>;
  type: Type;
  body: Option<Block>;
  is_generic: bool;
  parent: Parent;
  path: String;
}

struct Param: Node{
  name: String;
  type: Type;
  is_self: bool;
  is_deref: bool;
}

impl Method{
  func new(node: Node, name: String, type: Type): Method{
    return Method{.node, type_params: List<Type>::new(),
                 name: name, self: Option<Param>::None, params: List<Param>::new(),
                 type: type, body: Option<Block>::None, is_generic: false,
                 parent: Parent::None, path: String::new()};
  }
  func print(self): String{
    return Fmt::str(self);
  }
}


struct Simple{
  scope: Ptr<Type>;
  name: String;
  args: List<Type>;
}

impl Simple{
  func new(name: String): Simple{
    return Simple{scope: Ptr<Type>::new(), name: name, args: List<Type>::new()};
  }
  func new(name: String, args: List<Type>): Simple{
    return Simple{scope: Ptr<Type>::new(), name: name, args: args};
  }
  func new(scope: Type, name: String): Simple{
    return Simple{scope: Ptr<Type>::new(scope), name: name, args: List<Type>::new()};
  }
  func into(*self): Type{
    //return Type::Simple{*ptr::get(self, 0)};
    return Type::Simple{self};
  }
  func clone(self): Simple{
    return Simple{scope: self.scope.clone(), name: self.name.clone(), args: self.args.clone()};
  }
}

enum Type{
  Simple(type: Simple),
  Pointer(type: Box<Type>),
  Array(type: Box<Type>, size: i32),
  Slice(type: Box<Type>)
}

impl Type{
  func new(s: str): Type{
    return Type::new(String::new(s));
  }
  func new(s: String): Type{
    return Simple::new(s).into();
  }
  func new(s: String, args: List<Type>): Type{
    return Simple::new(s, args).into();
  }
  func new(scp: Type, s: String): Type{
    return Simple::new(scp, s).into();
  }
  func toPtr(*self): Type{
    return Type::Pointer{Box::new(self)};
  }
  
  func name(self): String*{
    if let Type::Simple(smp*)=(self){
      return &smp.name;
    }
    panic("cant Type::name() {}", self);
  }

  func is_simple(self): bool{
    return self is Type::Simple;
  }
  func as_simple(self): Simple*{
    if let Type::Simple(simple*) = (self){
      return simple;
    }
    panic("as_simple");
  }
  func unwrap_simple(*self): Simple{
    if let Type::Simple(simple) = (self){
      return simple;
    }
    Drop::drop(self);
    panic("as_simple");
  }

  func is_void(self): bool{
    let str = self.print();
    let res = str.eq("void");
    Drop::drop(str);
    return res;
  }
  func is_prim(self): bool{
    return prim_size(self.print()).is_some();
  }
  func is_unsigned(self): bool{
    let str = self.print();
    let res = str.eq("u8") || str.eq("u16") || str.eq("u32") || str.eq("u64");
    Drop::drop(str);
    return res;
  }
  func is_str(self): bool{
    return self.print().eq("str");
  }
  func eq(self, s: str): bool{
    let tmp = self.print();
    let res = tmp.eq(s);
    Drop::drop(tmp);
    return res;
  }
  func is_generic(self): bool{
    if let Type::Simple(smp*) = (self){
      return !smp.args.empty();
    }
    return false;
  }
  func get_args(self): List<Type>*{
    if let Type::Simple(smp*) = (self){
      return &smp.args;
    }
    panic("get_args {}", self);
  }
  func is_pointer(self): bool{
    return self is Type::Pointer;
  }
  func is_array(self): bool{
    return self is Type::Array;
  }
  func is_slice(self): bool{
    return self is Type::Slice;
  }
  func unwrap_ptr(self): Type*{
    if let Type::Pointer(bx*) = (self){
      return bx.get();
    }
    return self;
  }
  func elem(self): Type*{
    if let Type::Pointer(bx*) = (self){
      return bx.get();
    }
    if let Type::Array(bx*, sz) = (self){
      return bx.get();
    }
    if let Type::Slice(bx*) = (self){
      return bx.get();
    }
    panic("elem {}", self);
  }

  //get plain(generic)
  func erase(self): Type{
    if let Type::Simple(smp*) = (self){
      if(smp.scope.has()){
        return Type::new(smp.scope.unwrap(), smp.name.clone());
      }else{
        return Type::new(smp.name.clone());
      }
    }
    panic("erase {}", self);
  }
  
  func print(self): String{
    return Fmt::str(self);
  }

  func scope(self): Type*{
    if let Type::Simple(smp*) = (self){
      return smp.scope.get();
    }
    panic("Type::scope");
  }

}

impl Clone for Type{
  func clone(self): Type{
    return AstCopier::clone(self);
  }
}

struct ArgBind: Node{
  name: String;
  is_ptr: bool;
}

struct IfLet{
  ty: Type;
  args: List<ArgBind>;
  rhs: Expr;
  then: Box<Stmt>;
  els: Option<Box<Stmt>>;
}

struct ForStmt{
  v: Option<VarExpr>;
  e: Option<Expr>;
  u: List<Expr>;
  body: Box<Stmt>;
}


struct IfStmt{
  e: Expr;
  then: Box<Stmt>;
  els: Option<Box<Stmt>>;
}


enum Stmt{
    Block(x: Block),
    Var(ve: VarExpr),
    Expr(e: Expr),
    Ret(e: Option<Expr>),
    While(e: Expr, b: Block),
    If(e: IfStmt),
    IfLet(e: IfLet),
    For(e: ForStmt),
    Continue,
    Break,
    Assert(e: Expr)
}

impl Stmt{
  func print(self): String{
    return Fmt::str(self);
  }
}

struct Block{
  list: List<Stmt>;
}

impl Block{
  func new(): Block{
    return Block{List<Stmt>::new()};
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

struct Fragment: Node{
  name: String;
  type: Option<Type>;
  rhs: Expr;
}

struct Literal{
  kind: LitKind;
  val: String;
  suffix: Option<Type>;
}

enum LitKind{
  INT, STR, CHAR, BOOL, FLOAT
}

struct ArrAccess{
  arr: Box<Expr>;
  idx: Box<Expr>;
  idx2: Option<Box<Expr>>;
}

enum Expr: Node{
  Lit(val: Literal),
  Name(val: String),
  Call(mc: Call),
  Par(e: Box<Expr>),
  Type(val: Type),
  Unary(op: String, e: Box<Expr>),
  Infix(op: String, l: Box<Expr>, r: Box<Expr>),
  Access(scope: Box<Expr>, name: String),
  Obj(type: Type, args: List<Entry>),
  As(e: Box<Expr>, type: Type),
  Is(e: Box<Expr>, rhs: Box<Expr>),
  Array(list: List<Expr>, size: Option<i32>),
  ArrAccess(val: ArrAccess)
}

impl Expr{
  func print(self): String{
    return Fmt::str(self);
  }
}

struct Call{
  scope: Ptr<Expr>;
  name: String;
  type_args: List<Type>;
  args: List<Expr>;
  is_static: bool;
}

impl Call{
  func print(self): String{
    return Fmt::str(self);
  }
  func new(name: String): Call{
    return Call{scope: Ptr<Expr>::new(), name: name, type_args: List<Type>::new(), args: List<Expr>::new(), is_static: false};
  }
}

struct Entry{
  name: Option<String>;
  expr: Expr;
  isBase: bool;
}

func print5(e: Expr*){
  print("{}\n", e);
}