import parser/parser
import parser/lexer
import parser/ast
import parser/printer
import parser/method_resolver
import parser/utils
import parser/token
import std/map


impl Debug for Resolver{
  func debug(self, f: Fmt*){}
}
impl Debug for RType{
  func debug(self, f: Fmt*){}
}


struct Context{
  map: Map<String, Resolver>;
  root: String;
  prelude: List<String>;
}

impl Context{
  func new(src_dir: String): Context{
    let pre = List<String>::new(6);
    let arr = ["Box", "List", "str", "String", "Option", "ops"];
    for(let i = 0;i < arr.len();++i){
      pre.add(arr[i].str());
    }
    return Context{map: Map<String, Resolver>::new(), root: src_dir, prelude: pre};
  }
  func create_resolver(self, path: String): Resolver*{
    let res = self.map.get_ptr(&path);
    if(res.is_some()){
      return res.unwrap();
    }
    let r = Resolver::new(path, self);
    self.map.add(path, r);
    return self.map.get_ptr(&path).unwrap();
  }
  func get_resolver(self, is: ImportStmt*): Resolver*{
    let path = String::new(self.root.str());
    path.append("/");
    for(let i = 0;i < is.list.len();++i){
      let part = is.list.get_ptr(i);
      if(i > 0){
        path.append("/");
      }
      path.append(part.str());
    }
    path.append(".x");
    return self.create_resolver(path);
  }
}

func is_struct(type: Type*): bool{
  return !type.is_prim() && !type.is_pointer(); 
}

func isReturnLast(b: Block*): bool{
    let last = b.list.last();
    return isRet(last);
}

func isReturnLast(stmt: Stmt*): bool{
  if (isRet(stmt)) {
    return true;
  }
  if let Stmt::Block(b*)=(stmt){
    return isReturnLast(b);
  }
  return false;
}

func isRet(stmt: Stmt*): bool{
  if let Stmt::Expr(expr*)=(stmt){
    if let Expr::Call(mc*)=(expr){
      return mc.name.eq("panic");
    }
    return false;
  }
  return stmt is Stmt::Ret || stmt is Stmt::Continue || stmt is Stmt::Break;
}

func printMethod(m: Method*): String{
  let s = String::new();
  s.append(m.name);
  s.append("()");
  return s;
}

//trait method signature for type
func mangle2(m: Method*, type: Type*): String{
  let s = String::new();
  s.append(m.name);
  s.append("(");
  for(let i = 0;i < m.params.len();++i){
    s.append("_");
    let pstr = m.params.get_ptr(i).type.print();
    if(pstr.eq("Self")){
      s.append(type.print());
    }else{
      s.append(pstr);
    }
  }
  s.append(")");
  return s;
}

struct Scope{
  list: List<VarHolder>;
}
struct VarHolder{
  name: String;
  type: Type;
  prm: bool;
}

impl Scope{
  func new(): Scope{
    return Scope{list: List<VarHolder>::new()};
  }
  func find(self, name: String*): Option<VarHolder*>{
    for(let i = 0;i < self.list.len();++i){
      let vh = self.list.get_ptr(i);
      if(vh.name.eq(name)){
        return Option::new(vh);
      }
    }
    return Option<VarHolder*>::None;
  }
}
impl VarHolder{
  func new(name: String, type: Type, prm: bool): VarHolder{
    return VarHolder{name: name, type: type, prm: prm};
  }
}

//#derive(debug)
struct Resolver{
  unit: Unit;
  is_resolved: bool;
  is_init: bool;
  typeMap: Map<String, RType>;
  curMethod: Option<Method*>;
  curImpl: Option<Impl*>;
  scopes: List<Scope>;
  ctx: Context*;
  used_methods: List<Method*>;
}

struct Config{
  optimize_enum: bool;
}

/*enum Decl{
  Struct(sd: StructDecl*),
  Enum(ed: EnumDecl*)
}*/

struct RType{
  type: Type;
  trait: Option<Trait*>;
  method: Option<Method*>;
  value: Option<String>;
  targetDecl: Option<Decl*>;
  vh: Option<VarHolder*>;
}

impl RType{
  func new(s: str): RType{
    return RType::new(Type::new(s.str()));
  }
  func new(typ: Type): RType{
    return RType{typ, Option<Trait*>::None, Option<Method*>::None, Option<String>::None, Option<Decl*>::None, Option<VarHolder*>::None};
  }
  func clone(self): RType{
    let res = RType::new(self.type);
    res.trait = self.trait;
    res.method = self.method;
    res.value = self.value;
    return res;
  }
}

func join(list: List<String>*, sep: str): String{
  let s = String::new();
  for(let i = 0;i < list.len();++i){
    let path = list.get_ptr(i);
    s.append(path.str());
  }
  return s;
}

func contains(list: List<String>*, s: String*): bool{
  for(let i = 0;i < list.len();++i){
    if(list.get_ptr(i).eq(s)){
      return true;
    }
  }
  return false;
}

func has(arr: List<ImportStmt>*, is: ImportStmt*): bool{
  for (let i = 0;i < arr.len();++i) {
      let i1 = arr.get_ptr(i);
      let s1 = join(&i1.list, "/");
      let s2 = join(&is.list, "/");
      if (s1.eq(&s2)) return true;
  }
  return false;
}

impl Resolver{
  func new(path: String, ctx: Context*): Resolver{
    let lexer = Lexer::new(path);
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    print("%s\n%s\n",unit.path.cstr(), Fmt::str(unit).cstr());
    let map = Map<String, RType>::new();
    let res = Resolver{unit: *unit, is_resolved: false, is_init: false, typeMap: map, 
      curMethod: Option<Method*>::None, curImpl: Option<Impl*>::None, scopes: List<Scope>::new(), ctx: ctx,
      used_methods: List<Method*>::new()};
    return res;
  }

  func newScope(self){
    let sc = Scope::new();
    self.scopes.add(sc);
    print("newScope %d\n", self.scopes.len());
  }
  func dropScope(self){
    //self.scopes.remove(self.scopes.len() - 1);
    --self.scopes.count;
    print("dropped %d\n", self.scopes.len());
  }
  func addScope(self, name: String, type: Type, prm: bool){
    print("addScope %s: %s\n", name.cstr(), type.print().cstr());
    let scope = self.scopes.last();
    scope.list.add(VarHolder::new(name, type, prm));
  }
 
  func get_unit(self, path: String): Unit*{
    let r = self.ctx.create_resolver(path);
    return &r.unit;
  }

  func getPath(self, is: ImportStmt*): String {
    return Fmt::format("{}/{}.x", self.ctx.root.str(), join(&is.list, "/").str());
  }

  func get_imports(self): List<ImportStmt>{
    let imports = List<ImportStmt>::new();
    for (let i = 0;i < self.unit.imports.len();++i) {
        let is = self.unit.imports.get_ptr(i);
        //ignore prelude imports
        let rest = join(&is.list, "/");
        if (!contains(&self.ctx.prelude, &rest)) {
            imports.add(*is);
        }
    }
    for (let i = 0;i < self.ctx.prelude.len();++i) {
        let pre = self.ctx.prelude.get_ptr(i);
        //skip self unit being prelude
        let path = Fmt::format("{}/std/{}.x", self.ctx.root.str(), pre.str());
        if (self.unit.path.eq(&path)) continue;
        let is = ImportStmt::new();
        is.list.add("std".str());
        is.list.add(*pre);
        imports.add(is);
    }
    if (self.curMethod.is_some() && !self.curMethod.get().type_args.empty()) {
        let tmp = self.get_unit(self.curMethod.get().path).imports;
        for (let i = 0;i < tmp.len();++i) {
            let is = tmp.get_ptr(i);
            if (has(&imports, is)) continue;
            //skip self being cycle
            let iss = self.getPath(is);
            if (self.unit.path.eq(&iss)) continue;
            imports.add(*is);
        }
    }
    return imports;
}
  
  func resolve_all(self){
    if(self.is_resolved) return;
    print("resolve_all %s\n", self.unit.path.cstr());
    self.is_resolved = true;
    self.init();
    for(let i = 0;i < self.unit.items.len();++i){
      self.visit(self.unit.items.get_ptr(i));
    }
    self.dump();
  }

  func dump(self){
    print("---dump---");
    print("%d types\n", self.typeMap.len());
    for(let i = 0;i < self.typeMap.len();++i){
      let pair = self.typeMap.get_idx(i).unwrap();
      print("%s -> %s\n", pair.a.cstr(), Fmt::str(&pair.b.type).cstr());
    }
    print("scope count %d\n", self.scopes.len());
    for(let i = 0;i < self.scopes.len();++i){
      let scope = self.scopes.get_ptr(i);
      for(let j = 0;j < scope.list.len();++j){
        let vh = scope.list.get_ptr(j);
        print("%s:%s\n", vh.name.cstr(), vh.type.print().cstr());
      }
    }
  }

  func addType(self, name: String, res: RType){
    self.typeMap.add(name, res);
  }
  func addType(self, name: String*, res: RType){
    self.typeMap.add(*name, res);
  }
  
  func init(self){
    if(self.is_init) return;
    self.is_init = true;
    let newItems = List<Impl>::new();
    for(let i=0;i<self.unit.items.len();++i){
      let it = self.unit.items.get_ptr(i);
      //Fmt::str(it).dump();
      if let Item::Decl(decl)=(it){
        let res = RType::new(decl.type);
        self.addType(decl.type.print(), res);
      }else if let Item::Trait(tr*)=(it){
        let res = RType::new(tr.type);
        res.trait = Option::new(tr);
        self.addType(tr.type.print(), res);
      }else if let Item::Impl(imp)=(it){
        //pass
      }else if let Item::Type(name*, rhs*)=(it){
        let res = self.visit(rhs);
        self.addType(name, res);
      }
    }
  }

  func err(self, msg: String){
    self.err(msg.str());
  }
  func err(self, msg: str){
    panic("%s", msg.cstr());
  }
  func err(self, msg: str, node: Expr*){
    let str = Fmt::format("{}\n{} {}", self.unit.path.str(), msg, node.print().str());
    self.err(str.str());
  }

  func getType(self, e: Type*): Type{
    return self.visit(e).type;
  }  

  func visit(self, node: Item*){
    if let Item::Method(m*) = (node){
      self.visit(m);
    }else if let Item::Type(name, rhs) = (node){
      //pass
    }else if let Item::Impl(imp*) = (node){
      self.visit(imp);
    }else if let Item::Decl(decl*) = (node){
      if let Decl::Struct(fields*) = (decl){
        self.visit(decl, fields);
      }else if let Decl::Enum(variants*) = (decl){
        //self.visit(decl, variants);
      }
    }
    else{
      Fmt::str(node).dump();
      panic("item");
    }
  }

  func is_cyclic(self, type: Type*, target: Type*): bool{
    return true;
  }

  func visit(self, node: Decl*, fields: List<FieldDecl>*){
    if(node.is_generic) return;
    node.is_resolved = true;
    for(let i = 0;i < fields.len();++i){
      let fd = fields.get_ptr(i);
      self.visit(&fd.type);
      if(self.is_cyclic(&fd.type, &node.type)){
        self.err(Fmt::format("cyclic type {}", node.type.print().str()));
      }
    }
  }

  func visit(self, imp: Impl*){
    if(!imp.info.type_params.empty()){
      //generic
      return;
    }
    self.curImpl = Option::new(imp);
    //resolve non generic type args
    if(imp.info.trait_name.is_some()){
      //todo
      let required = Map<String, Method*>::new();
      let trait_rt = self.visit(imp.info.trait_name.get());
      let trait_decl = trait_rt.trait.unwrap();
      for(let i = 0;i < trait_decl.methods.len();++i){
        let m = trait_decl.methods.get_ptr(i);
        if(!m.body.is_some()){
          let mangled = mangle2(m, &imp.info.type);
          required.add(mangled, m);
        }
      }
      for(let i = 0;i < imp.methods.len();++i){
        let m = imp.methods.get_ptr(i);
        if(!m.type_args.empty()) continue;
        self.visit(m);
        let mangled = mangle2(m, &imp.info.type);
        let idx = required.indexOf(&mangled);
        if(idx != -1){
          required.remove(idx);
        }
      }
      if(!required.empty()){
        let msg = String::new();
        for(let i = 0;i < required.len();++i){
          let p = required.get_idx(i);
          msg.append("method ");
          msg.append(printMethod(p.unwrap().b));
          msg.append(" not implemented for ");
          msg.append(imp.info.trait_name.get().print());
          msg.append("\n");
        }
        self.err(msg);
      }
    }else{
      for(let i = 0;i < imp.methods.len();++i){
        let m = imp.methods.get_ptr(i);
        if(!m.type_args.empty()) continue;
        self.visit(m);
      }
    }
    self.curImpl = Option<Impl*>::None;
  }

  func visit(self, node: Method*){
    print("visiting %s\n", printMethod(node).cstr());
    if(node.is_generic){
      return;
    }
    self.curMethod = Option::new(node);
    let res = self.visit(&node.type);
    res.method = Option<Method*>::new(node);
    self.newScope();
    if(node.self.is_some()){
      self.visit(&node.self.get().type);
      self.addScope(node.self.get().name, node.self.get().type, true);
    }
    for(let i = 0;i<node.params.len();++i){
      let prm = node.params.get_ptr(i);
      self.visit(&prm.type);
      self.addScope(prm.name, prm.type, true);
    }
    if(node.body.is_some()){
      self.visit(node.body.get());
      //todo check unreachable
      if (!node.type.is_void() && !isReturnLast(node.body.get())) {
        let msg = String::new("non void function ");
        msg.append(printMethod(self.curMethod.unwrap()));
        msg.append(" must return a value");
        self.err(msg);
      }
    }
    self.dropScope();
    self.curMethod = Option<Method*>::None;
  }

  func addUsed(self, decl: Decl*){
    panic("add used");
  }

}


//expressions-------------------------------------
impl Resolver{
  func is_condition(self, e: Expr*): bool{
    let tmp = self.visit(e);
    return tmp.type.print().eq("bool");
  }

  func visit(self, node: Type*): RType{
    let str = node.print();
    let cached = self.typeMap.get_p(&str);
    if(cached.is_some()){
      return cached.unwrap();
    }
    if(node.is_prim() || node.is_void()){
      let res = RType::new(str.str());
      self.addType(str, res);
      return res;
    }
    if(node.is_pointer()){
      let inner = node.unwrap();
      let elem = self.visit(&inner);
      return RType::new(elem.type.toPtr());
    }
    if(node.is_slice()){
      let inner = node.elem();
      let elem = self.visit(&inner);
      return RType::new(Type::Slice{Box::new(elem.type)});      
    }
    panic("type %s", node.print().cstr());
  }

  func visit(self, node: Expr*): RType{
    if let Expr::Lit(kind, value, suffix*)=(node){
      if(suffix.is_some()){
        if(i64::parse(&value) > max_for(suffix.get())){
          self.err("literal out of range");
        }
        return self.visit(suffix.get());
      }
      if(kind is LitKind::INT){
        let res = RType::new("i32");
        res.value = Option::new(value);
        return res;
      }else if(kind is LitKind::STR){
        return RType::new("str");
      }else if(kind is LitKind::BOOL){
        return RType::new("bool");
      }else if(kind is LitKind::FLOAT){
        let res = RType::new("f32");
        res.value = Option::new(value);
        return res;
      }else if(kind is LitKind::CHAR){
        let res = RType::new("u32");
        res.value = Option::new(value);
        return res;
      }
    }else if let Expr::Infix(op*, lhs*, rhs*) = (node){
      return self.visit_infix(node, op, lhs.get(), rhs.get());
    }else if let Expr::Call(call*) = (node){
      return self.visit(call);
    }else if let Expr::Name(name*) = (node){
      for(let i = self.scopes.len() - 1;i >= 0;--i){
        let scope = self.scopes.get_ptr(i);
        let vh = scope.find(name);
        if(vh.is_some()){
          let vh2 = vh.unwrap();
          let res = self.visit(&vh2.type);
          res.vh = Option::new(vh2);
          return res;
        }
      }
      self.dump();
      self.err(Fmt::format("unknown identifier: {}", name.str()));
    }else if let Expr::Unary(op*, ebox*) = (node){
      return self.visit_unary(node, op, ebox.get());
    }else if let Expr::Par(expr*) = (node){
      return self.visit(expr.get());
    }
    panic("visit expr %s", node.print().cstr());
  }
  func visit_unary(self, node: Expr*, op: String*, e: Expr*): RType{
    if(op.eq("&")){
      return self.visit_ref(e);
    }
    if(op.eq("*")){
      return self.visit_deref(node, e);
    }
    let res = self.visit(e);
    if(op.eq("!")){
      if(!res.type.print().eq("bool")){
        self.err("unary on non bool", node);
      }
      return res;
    }
    if (res.type.print().eq("bool") || !res.type.is_prim()) {
      self.err("unary on non integer" , node);
    }
    if (op.eq("--") || op.eq("++")) {
      if (!(e is Expr::Name || e is Expr::Access)) {
          self.err("pre-incr/decr on non variable", node);
      }
    }
    //optimization?
    /*if (op.eq("-") && res.value.is_some()) {
      res.value = "-" + res.value.get();
    }*/   
    return res;
  }

  func visit_infix(self, node: Expr*, op: String*, lhs: Expr*, rhs: Expr*): RType{
    let lt = self.visit(lhs);
    let rt = self.visit(rhs);
    if(lt.type.is_void() || rt.type.is_void()){
      self.err("operation on void type");
    }
    if(lt.type.is_str() || rt.type.is_str()){
      self.err("string op not supported yet");
    }
    if(!(lt.type.is_prim() && rt.type.is_prim())){
      panic("infix on non prim type: %s", node.print().cstr());
    }
    if(is_comp(op)){
      return RType::new("bool");
    }
    else if(op.eq("&&") || op.eq("||")){
      if (!lt.type.print().eq("bool")) {
        panic("infix lhs is not boolean: %s", lhs.print().cstr());
      }
      if (!rt.type.print().eq("bool")) {
        panic("infix rhs is not boolean: %s", rhs.print().cstr());
      }        
      return RType::new("bool");
    }else{
      return RType::new(infix_result(lt.type.print().str(), rt.type.print().str()));
    }
    panic("%s\n", node.print().cstr());
  }

  func visit_ref(self, e: Expr*): RType{
    if(e is Expr::Name || e is Expr::Access || e is Expr::ArrAccess){
      let res = self.visit(e);
      res.type = res.type.toPtr();
      return res;
    }
    panic("ref expr is not supported: %s", e.print().cstr());
  }

  func visit_deref(self, node: Expr*, e: Expr*): RType{
    let inner = self.visit(e);
    if(!inner.type.is_pointer()){
      self.err(Fmt::format("deref expr is not pointer: %s -> %s", node.print().str(), inner.type.print().str()));
    }
    inner.type = inner.type.unwrap();
    return inner;
  }  

  func visit(self, call: Call*): RType{
    let sig = Signature::new(call, self);
    if(call.scope.is_some()){
      let mr = MethodResolver::new(self);
      return mr.handle(&sig);
    }
    if(call.name.eq("print")){
      return RType::new("void");
    }
    if(call.name.eq("panic")){
      if(!call.args.empty()){
        let arg = call.args.get_ptr(0);
        if let Expr::Lit(kind, val, sf) = (arg){
          if(kind is LitKind::STR){
            return RType::new("void");
          }
        }
        self.err(Fmt::format("invalid panic argument: {}", arg.print().str()));
      }
      return RType::new("void");
    }
    if(call.name.eq("malloc")){
      if(call.tp.empty()){
        return RType::new(Type::new("i8").toPtr());
      }else{
        let arg = self.visit(call.tp.get_ptr(0));
        return RType::new(arg.type.toPtr());
      }
    }
    panic("call %s", call.print().cstr());
  }
}

func infix_result(l: str, r: str): str{
  if(l.eq(r)){
    return l;
  }
  let arr = ["f64", "f32", "i64", "i32", "i16", "i8", "u64", "u32", "u16"];
  for(let i = 0;i < arr.len();++i){
    let op = arr[i];
    if(l.eq(op) || r.eq(op)){
      return op;
    }
  }
  panic("infix_result: %s, %s", l, r);
}

func is_comp(s: String*): bool{
  return s.eq("==") || s.eq("!=") || s.eq("<") || s.eq(">") || s.eq("<=") || s.eq(">=");
}

//statements-------------------------------------
impl Resolver{
  func visit(self, node: Stmt*){
    if let Stmt::Expr(e*) = (node){
      self.visit(e);
      return;
    }else if let Stmt::Ret(e) = (node){
      if(e.is_some()){
        //todo
        self.visit(e.get());
      }else{
        if(!self.curMethod.unwrap().type.is_void()){
          self.err("non-void method returns void");
        }
      }
      return;
    }else if let Stmt::Var(ve*) = (node){
      self.visit(ve);
      return;
    }else if let Stmt::Assert(e*) = (node){
      print("%s\n", e.print().cstr());
      if(!self.is_condition(e)){
        panic("assert expr is not bool: %s", e.print().cstr());
      }
      return;
    }else if let Stmt::If(e*, then*, els*) = (node){
      if (!self.is_condition(e)) {
        self.err("if condition is not a boolean", e);
      }
      self.newScope();
      self.visit(then.get());
      self.dropScope();
      if (els.is_some()) {
        self.newScope();
        self.visit(els.get().get());
        self.dropScope();
      }
      return;      
    }
    panic("visit stmt %s", node.print().cstr());
  }

  func visit(self, node: Block*){
    for(let i = 0;i < node.list.len();++i){
      self.visit(node.list.get_ptr(i));
    }
  }

  func visit(self, node: VarExpr*){
    for(let i = 0;i < node.list.len();++i){
      let f = node.list.get_ptr(i);
      let res = self.visit(f);
      self.addScope(f.name, res.type, false);
    }
  }

  func visit(self, node: Fragment*): RType{
    let rhs = self.visit(&node.rhs);
    if(node.type.is_none()){
      return rhs.clone();
    }
    let type = self.visit(node.type.get());
    return type;
  }
}