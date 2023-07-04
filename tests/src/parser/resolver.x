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
  scopes: List<Scope>;
}

struct Config{
  optimize_enum: bool;
}

struct RType{
  type: Type;
  trait: Option<Trait*>;
  method: Option<Method*>;
}

impl RType{
  func new(s: str): RType{
    return RType::new(Type::new(s.str()));
  }
  func new(typ: Type): RType{
    return RType{typ, Option<Trait*>::None, Option<Method*>::None};
  }
  func clone(self): RType{
    let res = RType::new(self.type);
    res.trait = self.trait;
    res.method = self.method;
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
      curMethod: Option<Method*>::None, scopes: List<Scope>::new()};
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
        panic("impl init");
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
  
  func resolve(self, node: Expr*): RType{
    return self.visit(node);
  }

  func visit(self, node: Item*){
    if let Item::Method(m) = (node){
      self.visit(&m);
    }else{
      Fmt::str(node).dump();
      panic("item");
    }
  }

  func visit(self, node: Type*): RType{
    let str = node.print();
    if(node.isPrim() || node.isVoid()){
      let res = RType::new(str.str());
      self.addType(str, res);
      return res;
    }
    panic("type %s", node.print().cstr());
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
      if (!node.type.isVoid() && !isReturnLast(node.body.get())) {
        let msg = String::new("non void function ");
        msg.append(printMethod(self.curMethod.unwrap()));
        msg.append(" must return a value");
        self.err(msg);
      }
    }
    self.dropScope();
    self.curMethod = Option<Method*>::None;
  }


  func visit(self, node: Stmt*){
    if let Stmt::Expr(e) = (node){
      self.visit(&e);
      return;
    }else if let Stmt::Ret(e) = (node){
      if(e.is_some()){
        //self.visit(&e);
      }else{
        if(!self.curMethod.unwrap().type.isVoid()){
          self.err("non-void method returns void");
        }
      }
      return;
    }else if let Stmt::Var(ve)=(node){
      self.visit(&ve);
      return;
    }
    panic("visit stmt %s", node.print().cstr());
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

      }
    }
    panic("visit expr %s", node.print().cstr());
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

func max_for(type: Type*): i64{
  let bits = prim_size(type.print()).unwrap() as i64;
  let tmp = 1 << (bits - 1);
  if(type.is_unsigned()){
    //do this not to overflow
    return tmp - 1 + tmp;
  }
  return tmp - 1;
}