import parser/parser
import parser/lexer
import parser/ast
import parser/printer
import std/map


func isReturnLast(b: Block*): bool{
    let last = b.list.last();
    return isRet(last);
}

func isReturnLast(stmt: Stmt*): bool{
  if (isRet(stmt)) {
    return true;
  }
  if let Stmt::Block(b)=(stmt){
    return isReturnLast(&b);
  }
  return false;
}

func isRet(stmt: Stmt*): bool{
  if let Stmt::Expr(expr)=(stmt){
    if let Expr::Call(mc)=(expr){
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
}

struct Config{
  optimize_enum: bool;
}

struct RType{
  type: Type;
  trait: Option<Trait*>;
  method: Option<Method*>;
  value: Option<String>;
}

impl RType{
  func new(s: str): RType{
    return RType::new(Type::new(s.str()));
  }
  func new(typ: Type): RType{
    return RType{typ, Option<Trait*>::None, Option<Method*>::None, Option<String>::None};
  }
  func clone(self): RType{
    let res = RType::new(self.type);
    res.trait = self.trait;
    res.method = self.method;
    res.value = self.value;
    return res;
  }
}


impl Resolver{
  func new(path: str): Resolver{
    let lexer = Lexer::new(path);
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    let map = Map<String, RType>::new();
    let res = Resolver{unit: *unit, is_resolved: false, is_init: false, typeMap: map, 
      curMethod: Option<Method*>::None, curImpl: Option<Impl*>::None, scopes: List<Scope>::new()};
    return res;
  }

  func newScope(self){
    self.scopes.add(Scope::new());
  }
  func dropScope(self){
    self.scopes.remove(self.scopes.len() - 1);
  }
  func addScope(self, name: String, type: Type, prm: bool){
    let scope = self.scopes.last();
    scope.list.add(VarHolder::new(name, type, prm));
  }
  
  func resolve_all(self){
    if(self.is_resolved) return;
    self.is_resolved = true;
    self.init();
    for(let i = 0;i < self.unit.items.len();++i){
      self.visit(self.unit.items.get_ptr(i));
    }
    self.dump();
  }

  func dump(self){
    print("%d types\n", self.typeMap.len());
    for(let i=0;i<self.typeMap.len();++i){
      let pair = self.typeMap.get_idx(i).unwrap();
      print("%s -> %s\n", pair.a.cstr(), Fmt::str(&pair.b.type).cstr());
    }
  }

  func addType(self, name: String, res: RType){
    self.typeMap.add(name, res);
  }
  
  func init(self){
    if(self.is_init) return;
    self.is_init = true;
    let newItems = List<Impl>::new();
    for(let i=0;i<self.unit.items.len();++i){
      let it = self.unit.items.get_ptr(i);
      //Fmt::str(it).dump();
      if let Item::Struct(sd)=(it){
        let res = RType::new(sd.type);
        self.addType(sd.type.print(), res);
      }else if let Item::Enum(ed)=(it){
        let res = RType::new(ed.type);
        self.addType(ed.type.print(), res);
      }else if let Item::Trait(tr)=(it){
        let res = RType::new(tr.type);
        res.trait = Option::new(&tr);
        self.addType(tr.type.print(), res);
      }else if let Item::Impl(imp)=(it){
        //pass
      }else if let Item::Type(name, rhs)=(it){
        let res = self.visit(&rhs);
        self.addType(name, res);
      }
    }
  }

  func err(self, msg: String){
    panic("%s", msg.cstr());
  }
  func err(self, msg: str){
    panic("%s", msg.cstr());
  }
  func err(self, msg: String, node: Node*){
    panic("%s\n:%d %s %s", self.unit.path.cstr(), node.line);
  }

  func visit(self, node: Item*){
    if let Item::Method(m) = (node){
      self.visit(&m);
    }else if let Item::Type(name, rhs) = (node){
      //pass
    }else if let Item::Impl(imp) = (node){
      if(imp.type_params.empty()){
        //generic
        return;
      }
      //self.curImpl = imp;
      //resolve non generic type args
      //let args = &imp.type;
      if(imp.trait_name.is_some()){
        //todo
        for(let i = 0;i < imp.methods.len();++i){
          self.visit(imp.methods.get_ptr(i));
        }
      }else{
        for(let i = 0;i < imp.methods.len();++i){
          self.visit(imp.methods.get_ptr(i));
        }
      }
    }else{
      Fmt::str(node).dump();
      panic("item");
    }
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




}

func max_for(type: Type*): i64{
  let bits: i64 = prim_size(type.print()).unwrap();
  let tmp = 1 << (bits - 1);
  if(type.is_unsigned()){
    //do this not to overflow
    return tmp - 1 + tmp;
  }
  return tmp - 1;
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
    panic("type %s", node.print().cstr());
  }

  func visit(self, node: Expr*): RType{
    if let Expr::Lit(kind, value, suffix)=(node){
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
    }else if let Expr::Infix(op, lhs, rhs) = (node){
      let lt = self.visit(lhs.get());
      let rt = self.visit(rhs.get());
      if(lt.type.is_void() || rt.type.is_void()){
        self.err("operation on void type");
      }
      if(lt.type.is_str() || rt.type.is_str()){
        self.err("string op not supported yet");
      }
      if(!(lt.type.is_prim() && rt.type.is_prim())){
        panic("infix on non prim type: %s", node.print().cstr());
      }
      if(is_comp(&op)){
        return RType::new("bool");
      }
      else if(op.eq("&&") || op.eq("||")){
        if (!lt.type.print().eq("bool")) {
          panic("infix lhs is not boolean: %s", lhs.get().print().cstr());
        }
        if (!rt.type.print().eq("bool")) {
          panic("infix rhs is not boolean: %s", rhs.get().print().cstr());
        }        
        return RType::new("bool");
      }else{
        return RType::new(infix_result(lt.type.print().str(), rt.type.print().str()));
      }
    }//else if let Expr::()
    panic("visit expr %s", node.print().cstr());
  }

}

func infix_result(l: str, r: str): str{
  if(l.eq(r)){
    return l;
  }
  let arr = ["f64", "f32", "i64", "i32", "i16", "i8", "u64", "u32", "u16"];
  for(let i = 0;i < arr.len;++i){
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
    if let Stmt::Expr(e) = (node){
      self.visit(&e);
      return;
    }else if let Stmt::Ret(e) = (node){
      if(e.is_some()){
        //self.visit(&e);
      }else{
        if(!self.curMethod.unwrap().type.is_void()){
          self.err("non-void method returns void");
        }
      }
      return;
    }else if let Stmt::Var(ve) = (node){
      self.visit(&ve);
      return;
    }else if let Stmt::Assert(e) = (node){
      if(!self.is_condition(&e)){
        panic("assert expr is not bool: %s", e.print().cstr());
      }
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