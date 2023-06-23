import parser/parser
import parser/lexer
import parser/ast
import std/map

//#derive(debug)
struct Resolver{
  unit: Unit;
  is_resolved: bool;
  is_init: bool;
  typeMap: Map<String, RType>;
}

struct Config{
  optimize_enum: bool;
}

struct RType{
  type: Type;
}

impl RType{
  func new(s: str): RType{
    return RType{Type::new(s.str())};
  }
  func new(typ: Type): RType{
    return RType{typ};
  }
}


impl Resolver{
  func new(path: str): Resolver{
    let lexer = Lexer::new(path);
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    let map = Map<String, RType>::new();
    let res = Resolver{unit: *unit, is_resolved: false, is_init: false, typeMap: map};
    return res;
  }
  
  func resolve_all(self){
    if(self.is_resolved) return;
    self.is_resolved = true;
    self.init();
    /*for(let i=0;i<self.unit.items.len();++i){
      visit(self.unit.items.get_ptr(i));
    }*/
  }
  
  func visit(node: Item*){
  }
  
  func init(self){
    if(self.is_init) return;
    self.is_init = true;
    let newItems = List<Impl>::new();
    for(let i=0;i<self.unit.items.len();++i){
      let it=self.unit.items.get_ptr(i);
      //Fmt::str(it).dump();
      if let Item::Struct(sd)=(it){
        let res = RType::new(sd.type);
        self.typeMap.add(sd.type.print(), res);
      }else{
        
      }
    }
  }
  
  func resolve(node: Expr): RType{
    panic("resolve");
  }
}