import parser/parser
import parser/lexer
import parser/ast
import parser/printer
import std/map


func isReturnLast(stmt: Stmt*): bool{
  if (isRet(stmt)) {
      return true;
  }
  if let Stmt::Block(b)=(stmt){
    let last = b.list.last();
    return isRet(last);
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
  else return false;
  return stmt is Stmt::Ret || stmt is Stmt::Continue || stmt is Stmt::Break;
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
    for(let i=0;i < self.unit.items.len();++i){
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
        let res = self.resolve(&rhs);
        self.addType(name, res);
      }
    }
  }
  
  func resolve(self, node: Expr*): RType{
    panic("resolve expr");
  }
  func resolve(self, node: Type*): RType{
    panic("resolve type");
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
    panic("type");
  }

  func visit(self, node: Method*){
    if(node.is_generic){
      return;
    }
    self.curMethod = Option::new(node);
    let res = self.resolve(&node.type);
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
        self.err("non void function must return a value");
      }
    }
    self.dropScope();
    self.curMethod = Option<Method*>::None;
  }

  func err(self, msg: String){
    panic(msg.cstr());
  }

  func visit(self, node: Stmt*){
    panic("visit stmt");
  }

}