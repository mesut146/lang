
import std/map
import std/libc
import parser/copier
import parser/printer
import parser/parser
import parser/token
import parser/lexer

static print_drops = false;

struct TokenStream{
  tokens: List<Token>;
}
impl TokenStream{
  func new(): TokenStream{
    return TokenStream{tokens: List<Token>::new()};
  }
  func add(self, tok: Token){
    self.tokens.add(tok);
  }
  func add(self, tt: TokenType, val: str){
    self.tokens.add(Token::new(tt, val));
  }
  func add(self, tt: TokenType, val: String){
    self.tokens.add(Token::new(tt, val));
  }
  func add(self, val: str){
    self.add(val.owned());
  }
  func add(self, val: String){
    let line = 0;
    let lexer = Lexer::from_string("<path>".owned(), val, line);
    while(true){
      let tok = lexer.next();
      if(tok.is(TokenType::EOF_)) break;
      self.tokens.add(tok);
    }
  }
}

func prim_size(s: str): Option<u32>{
  let prims = ["bool", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64"];
  let sizes = [8, 8, 16, 32, 64, 8, 16, 32, 64, 32, 64];
  for(let i = 0;i < prims.len();++i){
    if(prims[i].eq(s)){
      return Option::new(sizes[i] as u32);
    }
  }
  return Option<u32>::new();
}

func prim_size(s: String): Option<u32>{
  let res = prim_size(s.str());
  s.drop();
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
  last_id: i32;
}

impl Unit{
  func new(path: String): Unit{
    //print("Unit::new() {}\n", path);
    return Unit{
      path: path,
      last_line: 0,
      imports: List<ImportStmt>::new(),
      items: List<Item>::new(),
      last_id: -1
    };
  }

  func node(self, line: i32): Node{
    let id = ++self.last_id;
    return Node::new(id, line);
  }

  func get_globals(self): List<Global*>{
    let res = List<Global*>::new();
    for item in &self.items{
      if let Item::Glob(g*) = item{
        res.add(g);
      }
    }
    return res;
  }
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
  func str(self): String{
      let s = String::new();
      for(let i=0;i<self.list.len();i+=1){
          if(i>0) s.append("/");
          s.append(self.list.get(i));
      }
      return s;
  }
  func eq(self, is: ImportStmt*): bool{
      if(self.list.len() != is.list.len()) return false;
      return self.list.eq(&is.list);
  }
}

struct Attributes{
  list: List<Attribute>;
}
impl Attributes{
  func new(): Attributes{
    return Attributes{list: List<Attribute>::new()};
  }
  func has_attr(self, name: str): bool{
    for(let i = 0;i < self.list.len();++i){
      let at = self.list.get(i);
      if(at.is_simple(name)){
        return true;
      }
    }
    return false;
  }
}
struct Attribute{
  name: String;
  args: List<String>;
  is_call: bool;
}
impl Attribute{
  func new(name: String): Attribute{
    return Attribute{name: name, args: List<String>::new(), is_call: false};
  }
  func is_simple(self, name: str): bool{
    return !self.is_call && self.name.eq(name);
  }
  func is_call(self, name: str): bool{
    return self.is_call && self.name.eq(name);
  }
}

enum Item{
  Method(m: Method),
  Decl(decl: Decl),
  Impl(i: Impl),
  Trait(t: Trait),
  Type(name: String, rhs: Type),
  Extern(methods: List<Method>),
  Const(val: Const),
  Glob(gl: Global),
}

impl Item{
  func as_impl(self): Impl*{
    if let Item::Impl(imp*) = self{
      return imp;
    }
    panic("Item::as_impl()");
  }
}

struct Global: Node{
  name: String;
  type: Option<Type>;
  expr: Expr;
}

struct Const{
  name: String;
  type: Option<Type>;
  rhs: Expr;
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
    return ImplInfo{List<Type>::new(), Option<Type>::new(), type};
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
  attr: Attributes;
}

enum Decl: BaseDecl{
  Struct(fields: List<FieldDecl>),
  Enum(variants: List<Variant>),
  TupleStruct(fields: List<Type>),
}

impl Decl{
  func is_drop(self): bool{
    return self.attr.has_attr("drop");
  }
  /*func is_struct(self): bool{
    return self is Decl::Struct;
  }*/
  func is_enum(self): bool{
    return self is Decl::Enum;
  }
  func get_variants(self): List<Variant>*{
    if let Decl::Enum(variants*) = self{
      return variants;
    }
    panic("get_variants {:?}", self.type);
  }
  func get_fields(self): List<FieldDecl>*{
    if let Decl::Struct(fields*) = self{
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
    match self{
      Parent::Impl(info*) => return &info.type,
      Parent::Trait(type*) => return type,
      _ => panic("get_type"),
    }
  }
  func clone(self): Parent{
    match self{
      Parent::None => return Parent::None,
      Parent::Impl(info*) => return Parent::Impl{info.clone()},
      Parent::Trait(type*) => return Parent::Trait{type.clone()},
      Parent::Extern => return Parent::Extern,
    }
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
  is_vararg: bool;
  attr: Attributes;
}

struct Param: Node{
  name: String;
  type: Type;
  is_self: bool;
  is_deref: bool;
}

impl Method{
  func new(node: Node, name: String, type: Type): Method{
    return Method::new(node, name, type, "".str());
  }
  func new(node: Node, name: String, type: Type, path: String): Method{
    return Method{
      .node,
      type_params: List<Type>::new(),
      name: name,
      self: Option<Param>::new(),
      params: List<Param>::new(),
      type: type,
      body: Option<Block>::new(),
      is_generic: false,
      parent: Parent::None,
      path: path,
      is_vararg: false,
      attr: Attributes::new(),
    };
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
  func into(*self, line: i32): Type{
    let id = Node::new(-1, line);
    return Type::Simple{.id, self};
  }
  func clone(self): Simple{
    return Simple{scope: self.scope.clone(), name: self.name.clone(), args: self.args.clone()};
  }
}
// (params)=>ret
struct FunctionType{
  return_type: Type;
  params: List<Type>;
}
impl Clone for FunctionType{
  func clone(self): FunctionType{
    return FunctionType{return_type: self.return_type.clone(), params: self.params.clone()};
  }
}
struct LambdaType{
  return_type: Option<Type>;
  params: List<Type>;
  captured: List<Type>;
}

enum Type: Node{
  Simple(type: Simple),
  Pointer(type: Box<Type>),
  Array(type: Box<Type>, size: i32),
  Slice(type: Box<Type>),
  Function(type: Box<FunctionType>),
  Lambda(type: Box<LambdaType>),
}
impl Type{
  func new(name: str): Type{
    return Type::new(String::new(name));
  }
  func new(name: String): Type{
    return Simple::new(name).into(0);
  }
  func new(name: String, args: List<Type>): Type{
    return Simple::new(name, args).into(0);
  }
  func new(scp: Type, name: String): Type{
    return Simple::new(scp, name).into(0);
  }
  func toPtr(*self): Type{
    let id = Node::new(-1, self.line);
    return Type::Pointer{.id, Box::new(self)};
  }
  
  func name(self): String*{
    if let Type::Simple(smp*)=(self){
      return &smp.name;
    }
    panic("cant Type::name() {:?}", self);
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
      std::no_drop(self);
      return simple;
    }
    self.drop();
    panic("as_simple");
  }

  func is_void(self): bool{
    let str = self.print();
    let res = str.eq("void");
    str.drop();
    return res;
  }
  func is_prim(self): bool{
    return prim_size(self.print()).is_some();
  }
  func is_unsigned(self): bool{
    let str = self.print();
    let res = str.eq("u8") || str.eq("u16") || str.eq("u32") || str.eq("u64");
    str.drop();
    return res;
  }
  func is_float(self): bool{
    let str = self.print();
    let res = str.eq("f32") || str.eq("f64");
    str.drop();
    return res;
  }
  func is_str(self): bool{
    return self.eq("str");
  }
  func eq(self, s: str): bool{
    let tmp = self.print();
    let res = tmp.eq(s);
    tmp.drop();
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
    panic("get_args {:?}", self);
  }
  func is_pointer(self): bool{
    return self is Type::Pointer;
  }
  func is_dpointer(self): bool{
    return self.is_pointer() && self.elem().is_pointer();
  }
  func is_fpointer(self): bool{
    return self is Type::Function;
  }
  func is_lambda(self): bool{
      return self is Type::Lambda;
  }
  func is_any_pointer(self): bool{
    return self.is_pointer() || self.is_fpointer() || self.is_lambda();
  }
  func is_array(self): bool{
    return self is Type::Array;
  }
  func is_slice(self): bool{
    return self is Type::Slice;
  }
  func deref_ptr(self): Type*{
    if let Type::Pointer(bx*) = (self){
      return bx.get();
    }
    return self;
  }
  func unwrap_ptr(*self): Type{
    if let Type::Pointer(bx) = (self){
      return bx.unwrap();
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
    panic("elem {:?}", self);
  }
  func unwrap_elem(*self): Type{
    if let Type::Pointer(bx) = (self){
      return bx.unwrap();
    }
    if let Type::Array(bx, sz) = (self){
      return bx.unwrap();
    }
    if let Type::Slice(bx) = (self){
      return bx.unwrap();
    }
    panic("unwrap_elem {:?}", self);
  }
  func get_ft(self): FunctionType*{
    if let Type::Function(bx*) = (self){
      return bx.get();
    }
    panic("get_ft {:?}", self);
  }
  func unwrap_ft(*self): FunctionType{
    if let Type::Function(bx) = (self){
      return bx.unwrap();
    }
    panic("get_ft {:?}", self);
  }
  
  func get_lambda(self): LambdaType*{
    if let Type::Lambda(bx*) = (self){
      return bx.get();
    }
    panic("get_lambda {:?}", self);
  }

  //get plain(generic)
  func erase(self): Type{
    if let Type::Simple(smp*) = (self){
      if(smp.scope.has()){
        return Type::new(smp.scope.get().clone(), smp.name.clone());
      }else{
        return Type::new(smp.name.clone());
      }
    }
    panic("erase {:?}", self);
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

  func parse(input: str): Type{
    let parser = Parser::from_string(input.str(), 0);
    let res = parser.parse_type();
    parser.drop();
    return res;
  }

}
impl Clone for Type{
  func clone(self): Type{
    return AstCopier::clone(self);
  }
}
impl Eq for Type{
  func eq(self, other: Type*): bool{
    let s1 = self.print();
    let s2 = other.print();
    let res = s1.eq(&s2);
    s1.drop();
    s2.drop();
    return res;
  }
}

struct ForStmt{
  var_decl: Option<VarExpr>;
  cond: Option<Expr>;
  updaters: List<Expr>;
  body: Box<Body>;
}

struct ForEach{
  var_name: String;
  rhs: Expr;
  body: Block;
}

struct IfStmt{
  cond: Expr;
  then: Box<Body>;
  else_stmt: Ptr<Body>;
}

struct ArgBind: Node{
  name: String;
  is_ptr: bool;
}
struct IfLet{
  type: Type;
  args: List<ArgBind>;
  rhs: Expr;
  then: Box<Body>;
  else_stmt: Ptr<Body>;
}

enum Stmt: Node{
    Var(ve: VarExpr),
    Expr(e: Expr),
    Ret(e: Option<Expr>),
    While(cond: Expr, then: Box<Body>),
    For(e: ForStmt),
    ForEach(e: ForEach),
    Continue,
    Break
}

impl Stmt{
  func print(self): String{
    return Fmt::str(self);
  }
}

enum Body: Node{
  Block(val: Block),
  Stmt(val: Stmt),
  If(val: IfStmt),
  IfLet(val: IfLet)
}

impl Body{
  func line(self): i32{
    match self{
      Body::Block(b*) =>  return b.line,
      Body::If(is*) => return is.cond.line,
      Body::IfLet(il*) => return il.rhs.line,
      Body::Stmt(val*) => return val.line,
    }
  }
}

struct Block{
  list: List<Stmt>;
  line: i32;
  end_line: i32;
  return_expr: Option<Expr>;
}

impl Block{
  func new(line: i32, end_line: i32): Block{
    return Block{list: List<Stmt>::new(), line: line, end_line: end_line, return_expr: Option<Expr>::new()};
  }
  func print(self): String{
    return Fmt::str(self);
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
impl Literal{
  func trim_suffix(self): str{
    if(self.suffix.is_none()){
      return self.val.str();
    }
    let suffix_str = self.suffix.get().print();
    let res = self.val.substr(0, self.val.len() - suffix_str.len());
    suffix_str.drop();
    if(res.ends_with("_")){
      res = res.substr(0, res.len() - 1);
    }
    return res;
  }
}

enum LitKind{
  INT, STR, CHAR, BOOL, FLOAT
}

struct ArrAccess{
  arr: Box<Expr>;
  idx: Box<Expr>;
  idx2: Ptr<Expr>;
}

//todo use this
enum InfixOp{
  PLUS, MINUS, MUL, DIV, PERCENT, POW,
  AND, OR, XOR, NOT, LTLT, GTGT,
  LT, LTEQ, GT, GTEQ,
  EQ, PLUSEQ, MINUSEQ, MULEQ, DIVEQ, PERCENTEQ, POWEQ, ANDEQ, OREQ,
  NOTEQ, LTEQ, GTEQ, LTLTEQ, GTGTEQ
}

//fix-sort
enum Expr: Node{
  Lit(val: Literal),
  Name(val: String),
  Call(mc: Call),
  MacroCall(mc: MacroCall),
  Par(e: Box<Expr>),
  Type(val: Type),
  Unary(op: String, e: Box<Expr>),
  Infix(op: String, l: Box<Expr>, r: Box<Expr>),
  Access(scope: Box<Expr>, name: String),
  Obj(type: Type, args: List<Entry>),
  As(e: Box<Expr>, type: Type),
  Is(e: Box<Expr>, rhs: Box<Expr>),
  Array(list: List<Expr>, size: Option<i32>),
  ArrAccess(val: ArrAccess),
  Match(val: Box<Match>),
  Block(x: Box<Block>),
  If(e: Box<IfStmt>),
  IfLet(e: Box<IfLet>),
  Lambda(val: Lambda),
  Ques(e: Box<Expr>),
  //Tuple(elems: List<Expr>),
}
impl Expr{
  func print(self): String{
    return Fmt::str(self);
  }
  func get_call(self): Call*{
    if let Expr::Call(cx*) = (self){
      return cx;
    }
    panic("get_call {:?}", self);
  }
  func is_body(self): bool{
    return self is Expr::Block || self is Expr::If || self is Expr::IfLet;
  }
  func into_stmt(*self): Stmt{
    let id = *(self as Node*);
    return Stmt::Expr{.id, self};
  }
}
struct Lambda{
    params: List<LambdaParam>;
    return_type: Option<Type>;
    body: Box<LambdaBody>;
}
struct LambdaParam: Node{
    name: String;
    type: Option<Type>;
}
enum LambdaBody{
    Expr(node: Expr),
    Stmt(node: Stmt)
}

struct MacroCall{
  scope: Option<Type>;
  name: String;
  args: List<Expr>;
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

struct Match{
  expr: Expr;
  cases: List<MatchCase>;
}
impl Match{
  func has_none(self): Option<MatchCase*>{
    for case in &self.cases{
      if(case.lhs is MatchLhs::NONE){
        return Option::new(case);
      }
    }
    return Option<MatchCase*>::new();
  }
}

struct MatchCase{
  lhs: MatchLhs;
  rhs: MatchRhs;
  line: i32;
}
enum MatchLhs{
  NONE,
  ENUM(type: Type, args: List<ArgBind>),
  UNION(types: List<Type>)
}

enum MatchRhs{
  EXPR(e: Expr),
  STMT(stmt: Stmt)
}
impl MatchRhs{
  func new(e: Expr): MatchRhs{
    return MatchRhs::EXPR{e};
  }
  func new(stmt: Stmt): MatchRhs{
    return MatchRhs::STMT{stmt};
  }
}

