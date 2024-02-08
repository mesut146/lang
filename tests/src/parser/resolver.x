import parser/parser
import parser/lexer
import parser/ast
import parser/printer
import parser/method_resolver
import parser/method_resolver
import parser/utils
import parser/token
import parser/copier
import parser/derive
import std/map


struct Context{
  map: Map<String, Resolver>;
  root: String;
  prelude: List<String>;
}

struct Scope{
  list: List<VarHolder>;
}
struct VarHolder{
  name: String;
  type: Type;
  prm: bool;
}

//#derive(debug)
struct Resolver{
  unit: Unit;
  is_resolved: bool;
  is_init: bool;
  typeMap: Map<String, RType>;
  cache: Map<i32, RType>;
  curMethod: Option<Method*>;
  curImpl: Option<Impl*>;
  scopes: List<Scope>;
  ctx: Context*;
  used_methods: List<Method*>;
  generated_methods: List<Method>;
  inLoop: i32;
  used_types: List<Decl*>;
  generated_decl: List<Decl>;
}

struct Config{
  optimize_enum: bool;
}

struct RType{
  type: Type;
  trait: Option<Trait*>;
  method: Option<Method*>;
  value: Option<String>;
  targetDecl: Option<Decl*>;
  vh: Option<VarHolder*>;
}

enum TypeKind{
  Array,
  Slice,
  Pointer,
  Other
}

impl TypeKind{
  func new(type: Type*): TypeKind{
    if(type.is_array()){
      return TypeKind::Array;
    }
    if(type.is_slice()){
      return TypeKind::Slice;
    }
    if(type.is_pointer()){
      return TypeKind::Pointer;
    }
    return TypeKind::Other;
  }
}

impl Debug for Resolver{
  func debug(self, f: Fmt*){
    panic("Resolver::debug");
  }
}
impl Debug for RType{
  func debug(self, f: Fmt*){
    panic("RType::debug");
  }
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
  func create_resolver(self, path: String*): Resolver*{
    let res = self.map.get_ptr(path);
    if(res.is_some()){
      return res.unwrap();
    }
    let r = Resolver::new(path.clone(), self);
    self.map.add(path.clone(), r);
    return self.map.get_ptr(path).unwrap();
  }
  func create_resolver(self, path: str): Resolver*{
    let path2 = path.str();
    return self.create_resolver(&path2);
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
    return self.create_resolver(&path);
  }
}

func printMethod(m: Method*): String{
  let s = String::new();
  if let Parent::Impl(info*)=(&m.parent){
    s.append(info.type.print().str());
    s.append("::");
  }else if let Parent::Trait(type*)=(&m.parent){
    s.append(type.print().str());
    s.append("::");
  }
  s.append(&m.name);
  s.append("()");
  return s;
}

//trait method signature for type
func mangle2(m: Method*, type: Type*): String{
  let s = String::new();
  s.append(&m.name);
  s.append("(");
  let map = Map<String, Type>::new();
  map.add("Self".str(), type.clone());
  let copier = AstCopier::new(&map);
  for(let i = 0;i < m.params.len();++i){
    s.append("_");
    let prm_type = &m.params.get_ptr(i).type;
    s.append(copier.visit(prm_type).print().str());
  }
  s.append(")");
  return s;
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

impl RType{
  func new(s: str): RType{
    return RType::new(Type::new(s.str()));
  }
  func new(typ: Type): RType{
    return RType{typ, Option<Trait*>::None, Option<Method*>::None, Option<String>::None, Option<Decl*>::None, Option<VarHolder*>::None};
  }
  func clone(self): RType{
    return RType{type: self.type.clone(),
      trait: self.trait,
      method: self.method,
      value: self.value,
      targetDecl: self.targetDecl,
      vh: self.vh};
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

func dumpp(r: Resolver*){
  r.dump();
}

impl Resolver{
  func new(path: String, ctx: Context*): Resolver{
    let lexer = Lexer::new(path);
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    let map = Map<String, RType>::new();
    let res = Resolver{unit: *unit, is_resolved: false, is_init: false, typeMap: map,
      cache: Map<i32, RType>::new(),
      curMethod: Option<Method*>::None, curImpl: Option<Impl*>::None, scopes: List<Scope>::new(), ctx: ctx,
      used_methods: List<Method*>::new(), generated_methods: List<Method>::new(),
      inLoop: 0, used_types: List<Decl*>::new(1000),
      generated_decl: List<Decl>::new(1000)};
    return res;
  }

  func newScope(self){
    let sc = Scope::new();
    self.scopes.add(sc);
  }
  func dropScope(self){
    //self.scopes.remove(self.scopes.len() - 1);
    --self.scopes.count;
  }
  func addScope(self, name: String, type: Type, prm: bool){
    for(let i=0;i<self.scopes.len();++i){
      let s = self.scopes.get_ptr(i);
      if(s.find(&name).is_some()){
        panic("variable %s already exists\n", name.cstr());
      }
    }
    let scope = self.scopes.last();
    scope.list.add(VarHolder::new(name, type, prm));
  }
 
  func get_unit(self, path: String*): Unit*{
    let r = self.ctx.create_resolver(path);
    return &r.unit;
  }

  func getPath(self, is: ImportStmt*): String {
    return Fmt::format("{}/{}.x", self.ctx.root.str(), join(&is.list, "/").str());
  }

  func get_relative_root(path: str, root: str): str{
    //print("cur=" + path + ", root=" + root);
    if (path.starts_with(root)) {
        return path.substr(root.len() + 1);//+1 for slash
    }
    return path;
}

  func get_imports(self): List<ImportStmt>{
    let imports = List<ImportStmt>::new();
    let cur = get_relative_root(self.unit.path.str(), self.ctx.root.str());
    for (let i = 0;i < self.ctx.prelude.len();++i) {
      let pre = self.ctx.prelude.get_ptr(i);
      //skip self unit being prelude
      let path = Fmt::format("std/{}.x", pre.str());
      if (cur.eq(path.str())) continue;
      let is = ImportStmt::new();
      is.list.add("std".str());
      is.list.add(pre.clone());
      imports.add(is);
    }
    for (let i = 0;i < self.unit.imports.len();++i) {
        let is = self.unit.imports.get_ptr(i);
        //ignore prelude imports
        //let rest = join(&is.list, "/");
        if (!has(&imports, is)) {
            imports.add(*is);
        }
    }
    if (self.curMethod.is_some() && !self.curMethod.unwrap().type_args.empty()) {
        let tmp = self.get_unit(&self.curMethod.unwrap().path).imports;
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
    self.init_globals();
    for(let i = 0;i < self.unit.items.len();++i){
      self.visit(self.unit.items.get_ptr(i));
    }
    for(let i=0;i<self.generated_methods.len();++i){
      let gm = self.generated_methods.get_ptr(i);
      self.visit(gm);
    }
    //self.dump();
  }
  
  func init_globals(self){
    self.newScope();//globals
    for (let i=0;i<self.unit.globals.len();++i) {
        let g = self.unit.globals.get_ptr(i);
        let rhs = self.visit(&g.expr);
        if (g.type.is_some()) {
            let type = self.getType(g.type.get());
            //todo check
            let err_opt = MethodResolver::is_compatible(RType::new(rhs.type), &type);
            if (err_opt.is_some()) {
                let msg = Fmt::format("variable type mismatch {}\nexpected: {} got {}\n{}'", g.name.str(),type.print().str(),rhs.type.print().str(), err_opt.get().str());
                self.err(msg.str());
            }
        }
        self.addScope(g.name.clone(), rhs.type, false);
    }
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
    //print("addType %s->%s\n", name.cstr(), res.type.print().cstr());
    self.typeMap.add(name, res);
  }
  func addType(self, name: String*, res: RType){
    self.addType(name.clone(), res);
  }
  
  func init(self){
    if(self.is_init) return;
    self.is_init = true;
    let newItems = List<Item>::new();
    for(let i = 0;i < self.unit.items.len();++i){
      let it = self.unit.items.get_ptr(i);
      //Fmt::str(it).dump();
      if let Item::Decl(decl*)=(it){
        let res = RType::new(decl.type);
        res.targetDecl=Option::new(decl);
        self.addType(decl.type.name().clone(), res);
        //todo derive
        if(!decl.derives.empty()){
          let imp = generate_derive(decl, &self.unit);
          newItems.add(Item::Impl{imp});
        }
      }else if let Item::Trait(tr*)=(it){
        let res = RType::new(tr.type);
        res.trait = Option::new(tr);
        self.addType(tr.type.name().clone(), res);
      }else if let Item::Impl(imp*)=(it){
        //pass
      }else if let Item::Type(name*, rhs*)=(it){
        let res = self.visit(rhs);
        self.addType(name, res);
      }
    }
    for(let i=0;i<newItems.len();++i){
      let it = newItems.get(i);
      self.unit.items.add(it);
    }
  }

  func err(self, msg: String){
    self.err(msg.str());
  }
  func err(self, msg: str){
    if(self.curMethod.is_some()){
      print(printMethod(self.curMethod.unwrap()).cstr());
    }
    panic("%s", msg.cstr());
  }
  func err(self, node: Expr*, msg: str){
    let str = Fmt::format("{}:{}\n{} {}", self.unit.path.str(), i32::print(node.line).str(),msg, node.print().str());
    self.err(str.str());
  }
  func err(self, node: Stmt*, msg: str){
    let str = Fmt::format("{}\n{} {}", self.unit.path.str(), msg, node.print().str());
    self.err(str.str());
  }

  func getType(self, e: Type*): Type{
    let rt = self.visit(e);
    return rt.type;
  }
  func getType(self, e: Expr*): Type{
    let rt = self.visit(e);
    return rt.type;
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
    }else if let Item::Trait(tr*) = (node){
    }else if let Item::Extern(methods*) = (node){
      for(let i=0;i<methods.len();++i){
        let m=methods.get_ptr(i);
        if(m.is_generic) continue;
        self.visit(m);
      }
    }
    else{
      Fmt::str(node).dump();
      panic("visitItem");
    }
  }

  func is_cyclic(self, type0: Type*, target: Type*): bool{
    let rt = self.visit(type0); 
    let type = &rt.type;
    if (type.is_pointer()) return false;
    if (type.is_array()) {
        return self.is_cyclic(type.elem(), target);
    }
    if (type.is_slice()) return false;
    if (!is_struct(type)) return false;
    if (type.print().eq(target.print().str())) {
        return true;
    }
    let bd = rt.targetDecl.unwrap();
    //print("bd %s\n", Fmt::str(bd).cstr());
    let base = bd.base;
    if (base.is_some()) {
      if(self.is_cyclic(base.get(), target)){
        return true;
      }
    }
    if let Decl::Enum(variants*)=(bd) {
        for (let i=0;i<variants.len();++i) {
            let ev = variants.get_ptr(i);
            for (let j=0;j<ev.fields.len();++j) {
                let f = ev.fields.get_ptr(j);
                if (self.is_cyclic(&f.type, target)) {
                    return true;
                }
            }
        }
    } else if let Decl::Struct(fields*)=(bd){
            for (let j=0;j<fields.len();++j) {
                let f = fields.get_ptr(j);
                if (self.is_cyclic(&f.type, target)) {
                    return true;
                }
            }
    }
    return false;
  }

  func visit(self, node: Decl*, fields: List<FieldDecl>*){
    if(node.is_generic) return;
    node.is_resolved = true;
    if(node.base.is_some()){
      self.visit(node.base.get());
    }
    for(let i = 0;i < fields.len();++i){
      let fd = fields.get_ptr(i);
      self.visit(&fd.type);
      if(self.is_cyclic(&fd.type, &node.type)){
        self.err(Fmt::format("cyclic type {}", node.type.print().str()).str());
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
        if(m.body.is_none()){
          let mangled = mangle2(m, &imp.info.type);
          required.add(mangled, m);
        }
      }
      for(let i = 0;i < imp.methods.len();++i){
        let m = imp.methods.get_ptr(i);
        if(!m.type_args.empty()) continue;
        self.visit(m);
        let mangled = mangle2(m, &imp.info.type);
        //print("impl %s\n", mangled.cstr());
        let idx = required.indexOf(&mangled);
        if(idx != -1){
          required.remove(idx);
        }
      }
      if(!required.empty()){
        let msg = String::new();
        for(let i = 0;i < required.len();++i){
          let p = required.get_idx(i).unwrap();
          msg.append("method ");
          msg.append(p.a.str());
          msg.append(" ");
          msg.append(printMethod(p.b).str());
          msg.append(" not implemented for ");
          msg.append(imp.info.type.print().str());
          msg.append("\n");
        }
        self.err(msg.str());
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
    //print("visiting %s\n", printMethod(node).cstr());
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
        msg.append(printMethod(self.curMethod.unwrap()).str());
        msg.append(" must return a value");
        self.err(msg.str());
      }
    }
    self.dropScope();
    self.curMethod = Option<Method*>::None;
  }

  func addUsed(self, decl: Decl*): Decl*{
    for(let i = 0;i < self.used_types.len();++i){
      let used = self.used_types.get(i);
      if(used.type.print().eq(decl.type.print().str())){
        return used;
      }
    }
    //print("addUsed %s\n", decl.type.print().cstr());
    self.used_types.add(decl);
    if(decl.base.is_some()){
      self.visit(decl.base.get());
    }
    if(decl is Decl::Struct){
      let fields = decl.get_fields();
      for(let i = 0;i < fields.len();++i){
        let fd = fields.get_ptr(i);
        self.visit(&fd.type);
      }
    }else{
      let variants = decl.get_variants();
      for(let i = 0;i < variants.len();++i){
        let ev = variants.get_ptr(i);
        for(let j = 0;j < ev.fields.len();++j){
          let f = ev.fields.get_ptr(j);
          self.visit(&f.type);
        }
      }
    }
    return *self.used_types.last();
  }
  
  func addUsed(self, m: Method*){
    let mng = mangle(m);
    for(let i=0;i<self.used_methods.len();++i){
      let prev = self.used_methods.get(i);
      if(mangle(prev).eq(mng.str())) return;
    }
    self.used_methods.add(m);
  }
  
  func visit(self, node: FieldDecl*): RType{
    return self.visit(&node.type);
  }
}


//expressions-------------------------------------
impl Resolver{
  func is_condition(self, e: Expr*): bool{
    let tmp = self.visit(e);
    return tmp.type.print().eq("bool");
  }

  func visit(self, node: Type*): RType{
    let id = Node::new(-1);
    let expr = Expr::Type{.id, *node};
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
      let inner = node.unwrap_ptr();
      let res = self.visit(inner);
      let ptr = res.type.toPtr();
      res.type = ptr;
      return res;
    }
    if(node.is_slice()){
      let inner = node.elem();
      let elem = self.visit(inner);
      return RType::new(Type::Slice{Box::new(elem.type)});      
    }
    if let Type::Array(inner*, size) = (node){
      let elem = self.visit(inner.get());
      return RType::new(Type::Array{Box::new(elem.type), size});      
    }
    if (str.eq("Self") && !self.curMethod.unwrap().parent.is_none()) {
      let imp = self.curMethod.unwrap().parent.as_impl();
      return self.visit(&imp.type);
    }
    let simple = node.as_simple();
    if (simple.scope.is_some()) {
      let scope = self.visit(simple.scope.get());
      let decl = scope.targetDecl.unwrap();
      if (!(decl is Decl::Enum)) {
          panic("type scope is not enum: %s", str.cstr());
      }
      //enum variant creation
      
      findVariant(decl, &simple.name);
      let ds = decl.type.print();
      let res = self.getTypeCached(&ds);
      self.addType(str, res);
      return res;
    }
    let target0 = Option<Decl*>::None;
    let targs = node.get_args();
    if (!targs.empty()) {
      for (let i = 0; i < targs.len();++i) {
          self.visit(targs.get_ptr(i));
      }
      //we looking for generic type
      let name = node.name();
      if (self.typeMap.contains(name)) {
          target0 = self.typeMap.get_ptr(name).unwrap().targetDecl;
      } else {
          //generic from imports
      }
    }
    if(target0.is_none()){
      let imp_result = self.find_imports(node.as_simple(), &str);
      if(imp_result.is_some()){
        let tmp = imp_result.unwrap();
        if(tmp.trait.is_some()){
          return tmp;
        }
        else if(tmp.targetDecl.is_some()){
          target0 = tmp.targetDecl;
          if(!target0.unwrap().is_generic){
            return tmp;
          }
        }else{
          //type alias from imports
          return tmp;
        }
      }
      else{
        self.err(&expr, "couldn't find type");
      }
    }
    let target = target0.unwrap();
    //generic
    if (node.get_args().empty() || !target.is_generic) {
        //inferred later
        let res = RType::new(target.type);
        res.targetDecl = Option::new(target);
        self.addType(str, res);
        return res;
    }
    if (node.get_args().len() != target.type.get_args().len()) {
      self.err(&expr, "type arguments size not matched");
    }
    /*if(target.is_generic){

    }*/
    //print("target %s\n", Fmt::str(target).cstr());
    let map = make_type_map(node.as_simple(), target);
    let copier = AstCopier::new(&map);
    let decl0 = copier.visit(target);
    self.generated_decl.add(decl0);
    let decl = self.generated_decl.last();
    self.addUsed(decl);
    //print("generated %s\n%s\n", decl.type.print().cstr(), self.unit.path.cstr());
    let smp = Simple::new(node.name().clone());
    let args = node.get_args();
    for (let i=0;i < args.len();++i) {
        let ta =  args.get_ptr(i);
        smp.args.add(ta.clone());
    }
    let res = RType::new(smp.into());
    res.targetDecl = Option::new(decl);
    self.addType(str, res);
    return res;
  }

  func make_type_map(type: Simple*, decl: Decl*): Map<String, Type>{
    let map = Map<String, Type>::new();
    let params = decl.type.get_args();
    for(let i = 0;i < type.args.len();++i){
      let arg = type.args.get_ptr(i);
      let prm = params.get_ptr(i);
      map.add(prm.name().clone(), arg.clone());
    }
    return map;
  }


  func find_imports(self, type: Simple*, str: String*): Option<RType>{
    let arr = self.get_imports();
    for (let i=0;i < arr.len();++i) {
      let is = arr.get_ptr(i);
      let resolver = self.ctx.get_resolver(is);
      resolver.init();
      //try full type
      let cached = resolver.typeMap.get_ptr(str);
      if (cached.is_some()) {
          let res = cached.unwrap();
          //let res = *cached.unwrap();
          self.addType(str.clone(), res.clone());
          if (res.targetDecl.is_some()) {
              if (!res.targetDecl.unwrap().is_generic) {
                  self.addUsed(res.targetDecl.unwrap());
              }
          }
          //todo trait
          return Option::new(res.clone());
      }
      if (!type.args.empty()) {
          //generic type
          //try root type
          let cached2 = resolver.typeMap.get_ptr(&type.name);
          if (cached2.is_some() && cached2.unwrap().targetDecl.is_some()){
              return Option::new(cached2.unwrap().clone());
          }
      }
    }
    return Option<RType>::None;
  }
  
  func findVariant(decl: Decl*, name: String*): i32{
    let variants = decl.get_variants();
    for(let i=0;i<variants.len();++i){
      let v = variants.get_ptr(i);
      if(v.name.eq(name)){
        return i;
      }
    }
    panic("unknown variant %s::%s", decl.type.print().cstr(), name.cstr());
  }

  func getTypeCached(self, str: String*): RType{
    let res = self.typeMap.get_p(str);
    if(res.is_some()){
      return res.unwrap();
    }
    panic("not cached %s", str.cstr());
  }

  
  
  func findField(self, node: Expr*, name: String*, decl: Decl*, type: Type*): Pair<Decl*, i32>{
    let cur = decl;
    while (true) {
        if (cur is Decl::Struct) {
            let fields=cur.get_fields();
            let idx = 0;
            for (let i=0;i<fields.len();++i) {
                let fd=fields.get_ptr(i);
                if (fd.name.eq(name)) {
                    return Pair::new(cur, idx);
                }
                ++idx;
            }
        }
        if (cur.base.is_some()) {
            let base = self.visit(cur.base.get()).targetDecl;
            if(base.is_none()) break;
            cur = base.unwrap();
        } else {
            break;
        }
    }
    let msg = Fmt::format("invalid field {} of {}", name.str(),type.print().str()); 
    self.err(node, msg.str());
    panic("");
  }
  
  func visit_access(self, node: Expr*, scope: Expr*, name: String*): RType{
    let scp = self.visit(scope);
    if (scp.targetDecl.is_none()) {
      let msg=Fmt::format("invalid field {} of {}", name.str(),scp.type.print().str()); 
      self.err(node, msg.str());
    }
    let decl = scp.targetDecl.unwrap();
    let pair = self.findField(node, name, decl, &scp.type);
    let fd = pair.a.get_fields().get_ptr(pair.b);
    return self.visit(fd);
  }
  
  func fieldIndex(arr: List<FieldDecl>*, name: str, type: Type*): i32{
    for(let i=0;i<arr.len();++i){
      let fd = arr.get_ptr(i);
      if(fd.name.eq(name)){
        return i;
      }
    }
    panic("unknown field %s.%s", type.print().cstr(), name.cstr());
  }
  
  func visit_obj(self, node: Expr*, type0: Type*, args: List<Entry>*): RType{
    let hasNamed = false;
    let hasNonNamed = false;
    let base = Option<Expr*>::new();
    for (let i=0;i<args.len();++i) {
        let e = args.get_ptr(i);
        if (e.isBase) {
            if (base.is_some()) self.err(node, "base already set");
            base = Option::new(&e.expr);
        } else if (e.name.is_some()) {
            hasNamed = true;
        } else {
            hasNonNamed = true;
        }
    }
    if (hasNamed && hasNonNamed) {
        self.err(node, "obj creation can't have mixed values");
    }
    //print("obj %s\n", node.print().cstr());
    let res = self.visit(type0);
    let decl = res.targetDecl.unwrap();
    if (decl.base.is_some() && base.is_none()) {
        self.err(node, "base class is not initialized");
    }
    if (decl.base.is_none() && base.is_some()) {
        self.err(node, "wasn't expecting base");
    }
    if (base.is_some()) {
        let base_ty = self.visit(base.unwrap()).type;
        if (!base_ty.print().eq(decl.base.get().print().str())){
            let msg = Fmt::format("invalid base class type: {} expecting {}", base_ty.print().str(), decl.base.get().print().str());
            self.err(node, msg.str());
        }
    }
    let fields0 = Option<List<FieldDecl>*>::new();
    let type = Type::new("");
    
    if let Decl::Enum(variants*)=(decl){
        let idx = findVariant(decl, type0.name());
        let variant = variants.get_ptr(idx);
        fields0 = Option::new(&variant.fields);
        type = Type::new(decl.type, variant.name.clone());
    }else if let Decl::Struct(f*)=(decl){
        fields0 = Option::new(f);
        type = decl.type;
        if (decl.is_generic) {
            //infer
            let inferred = self.inferStruct(node, &decl.type, hasNamed, f, args);
            res = self.visit(&inferred);
            //let map = get_type_map(&inferred, decl);
            //let copier = AstCopier::new(&map);
            let gen_decl = res.targetDecl.unwrap();
            //res = self.visit(&gen_decl.type);
            fields0 = Option::new(gen_decl.get_fields());
            //self.addUsed(gen_decl);
            
        }
    }
    let fields=fields0.unwrap();
    
    let field_idx = 0;
    let names=List<String>::new();
    for (let i = 0; i < args.len(); ++i) {
        let e = args.get_ptr(i);
        if (e.isBase) continue;
        let prm_idx = 0;
        if (hasNamed) {
            names.add(e.name.unwrap());
            prm_idx = fieldIndex(fields, e.name.get().str(), &type);
        } else {
            prm_idx = field_idx;
            ++field_idx;
        }
        let prm = fields.get_ptr(prm_idx);
        //todo if we support unnamed fields, change this
        if (!hasNamed) {
            names.add(prm.name);
        }
        let pt = self.getType(&prm.type);
        let arg = self.visit(&e.expr);
        if (MethodResolver::is_compatible(arg, &pt).is_some()) {
            let f = Fmt::format("field type is imcompatiple {}\n expected: {} got: {}", e.expr.print().str(), pt.print().str(), arg.type.print().str());
            self.err(node, f.str());
        }
    }
    //check non set fields
    for (let i=0;i<fields.len();++i) {
        let fd=fields.get_ptr(i);
        if (!names.contains(&fd.name)) {
            let msg=Fmt::format("field not set: {}", fd.name.str());
            self.err(node, msg.str());
        }
    }
    return res;
  }

  func inferStruct(self, node: Expr*, type: Type*, hasNamed: bool, fields: List<FieldDecl>* ,args: List<Entry>*): Type{
    let inferMap = Map<String, Option<Type>>::new();
    let typeArgs = type.get_args();
    for (let i=0;i<typeArgs.len();++i) {
        let ta = typeArgs.get_ptr(i);
        inferMap.add(ta.name().clone(), Option<Type>::None);
    }
    for (let i = 0; i < args.len(); ++i) {
        let e = args.get_ptr(i);
        let prm_idx = 0;
        if (hasNamed) {
            prm_idx = fieldIndex(fields, e.name.get().str(), type);
        } else {
            prm_idx = i;
        }
        let arg_type = self.visit(&e.expr);
        let target_type = &fields.get_ptr(i).type;
        MethodResolver::infer(&arg_type.type, target_type, &inferMap);
    }
    let res = Simple::new(type.name().clone());
    for (let i = 0;i < inferMap.len();++i) {
        let p = inferMap.get_idx(i).unwrap(); 
        if (p.b.is_none()) {
            self.err(node, Fmt::format("can't infer type parameter: {}", p.a.str()).str());
        }
        res.args.add(p.b.unwrap());
    }
    return res.into();
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
        self.err(node, "unary on non bool");
      }
      return res;
    }
    if (res.type.print().eq("bool") || !res.type.is_prim()) {
      self.err(node, "unary on non integer");
    }
    if (op.eq("--") || op.eq("++")) {
      if (!(e is Expr::Name || e is Expr::Access)) {
          self.err(node, "pre-incr/decr on non variable");
      }
    }
    //optimization?
    /*if (op.eq("-") && res.value.is_some()) {
      res.value = "-" + res.value.get();
    }*/   
    return res;
  }

  func is_assign(s: str): bool{
    return s.eq("=") || s.eq("+=") || s.eq("-=") || s.eq("*=") || s.eq("/=");
  }

  func visit_assign(self, node: Expr*, op: String*, lhs: Expr*, rhs: Expr*): RType{
    let t1 = self.visit(lhs);
    let t2 = self.visit(rhs);
    if (MethodResolver::is_compatible(t2, &t1.type).is_some()) {
      let msg = Fmt::format("cannot assign %s=%s", t1.type.print().str(), t2.type.print().str());
      self.err(node, msg.str());
    }
    return t1;
  }

  func visit_infix(self, node: Expr*, op: String*, lhs: Expr*, rhs: Expr*): RType{
    if(is_assign(op.str())){
      return self.visit_assign(node, op, lhs, rhs);
    }
    let lt = self.visit(lhs);
    let rt = self.visit(rhs);
    if(lt.type.is_void() || rt.type.is_void()){
      self.err(node, "operation on void type");
    }
    if(lt.type.is_str() || rt.type.is_str()){
      self.err(node, "string op not supported yet");
    }
    if(!(lt.type.is_prim() && rt.type.is_prim())){
      self.err(node, "infix on non prim type");
    }
    if(is_comp(op.str())){
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
      self.err(Fmt::format("deref expr is not pointer: {} -> {}", node.print().str(), inner.type.print().str()));
    }
    inner.type = inner.type.unwrap_ptr().clone();
    return inner;
  }

  func is_special(self, mc: Call*, name: str, kind: TypeKind): bool{
    if (mc.scope.is_none() || !mc.name.eq(name) || !mc.args.empty()) {
      return false;
    }
    let scope = self.getType(mc.scope.get().get()).unwrap_ptr();
    return TypeKind::new(scope) is kind;
  }
  
  func is_slice_get_ptr(self, mc: Call*): bool{
        if (!mc.scope.is_some() || !mc.name.eq("ptr") || !mc.args.empty()) {
            return false;
        }
        let scope = self.getType(mc.scope.get().get()).unwrap_ptr();
        return scope.is_slice();
   }
   func is_slice_get_len(self, mc: Call*): bool{
        if (!mc.scope.is_some() || !mc.name.eq("len") || !mc.args.empty()) {
            return false;
        }
        let scope = self.getType(mc.scope.get().get()).unwrap_ptr();
        return scope.is_slice();
  }
  //x.ptr()
  func is_array_get_ptr(self, mc: Call*): bool{
        if (!mc.scope.is_some() || !mc.name.eq("ptr") || !mc.args.empty()) {
            return false;
        }
        let scope = self.getType(mc.scope.get().get()).unwrap_ptr();
        return scope.is_array();
   }
   //x.len()
   func is_array_get_len(self, mc: Call*): bool{
        if (!mc.scope.is_some() || !mc.name.eq("len") || !mc.args.empty()) {
            return false;
        }
        let scope = self.getType(mc.scope.get().get()).unwrap_ptr();
        return scope.is_array();
  }
  
  func is_ptr_get(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().get().print().eq("ptr") && mc.name.eq("get");
  }

  func visit(self, node: Expr*, call: Call*): RType{
    if(is_ptr_get(call)){
      if (call.args.len() != 2) {
        self.err(node, "ptr access must have 2 args");
      }
      let arg = self.getType(call.args.get_ptr(0));
      if (!arg.is_pointer()) {
          self.err(node, "ptr arg is not ptr");
      }
      let idx = self.getType(call.args.get_ptr(1)).print();
      if (idx.eq("i32") || idx.eq("i64") || idx.eq("u32") || idx.eq("u64") || idx.eq("i8") || idx.eq("i16")) {
          return self.visit(&arg);
      } else {
          self.err(node, "ptr access index is not integer");
      }
    }
    if (self.is_slice_get_ptr(call)) {
        let elem = self.getType(call.scope.get().get()).elem();
        return RType::new(elem.toPtr());
    }
    if (self.is_slice_get_len(call)) {
        self.visit(call.scope.get().get());
        let type = as_type(SLICE_LEN_BITS());
        return RType::new(type);
    }
    if(self.is_array_get_len(call)){
      self.visit(call.scope.get().get());
      return RType::new("i64");
    }
    if(self.is_array_get_ptr(call)){
      let arr_type = self.getType(call.scope.get().get()).unwrap_ptr();
      return RType::new(arr_type.elem().toPtr());
    }
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
        if let Expr::Lit(lit*) = (arg){
          if(lit.kind is LitKind::STR){
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
    if (call.name.eq("panic")) {
        if (call.args.empty()) {
            return RType::new("void");
        }
        let arg = call.args.get_ptr(0);
        if let Expr::Lit(lit*)=(arg){
          if(lit.kind is LitKind::STR){
            return RType::new("void");
          }
        }
        self.err(node, "invalid panic argument: ");
    }
    let mr = MethodResolver::new(self);
    return mr.handle(&sig);
  }
  
  func visit_arr_access(self, node: Expr*, aa: ArrAccess*): RType{
    let arr = self.getType(aa.arr.get());
    let idx = self.getType(aa.idx.get());
    //todo unsigned
    if (idx.print().eq("bool") || !idx.is_prim()){
      self.err(node, "array index is not an integer");
    }

    if (aa.idx2.is_some()) {
        let idx2 = self.getType(aa.idx2.get().get());
        if (idx2.print().eq("bool") || !idx2.is_prim()){
          self.err(node, "range end is not an integer");
        }
        let inner = arr.unwrap_ptr();
        if (inner.is_slice()) {
            return RType::new(inner.clone());
        } else if (inner.is_array()) {
            return RType::new(Type::Slice{Box::new(inner.elem().clone())});
        } else if (arr.is_pointer()) {
            //from raw pointer
            return RType::new(Type::Slice{Box::new(inner.clone())});
        } else {
            self.err(node, "cant make slice out of ");
        }
    }
    if (arr.is_pointer()) {
        arr = self.getType(arr.elem());
    }
    if (arr.is_array() || arr.is_slice()) {
        return self.visit(arr.elem());
    }
    self.err(node, "cant index: ");
    panic("");
  }
  
  func visit_array(self, node: Expr*, list: List<Expr>*, size: Option<i32>*): RType{
    if (size.is_some()) {
        let e = self.visit(list.get_ptr(0));
        //let elemType = self.getType(list.get_ptr(0));
        let elemType = e.type;
        return RType::new(Type::Array{Box::new(elemType), size.unwrap()});
    }
    let elemType = self.getType(list.get_ptr(0));
    for (let i = 1; i < list.len(); ++i) {
        let cur = self.visit(list.get_ptr(i));
        let cmp = MethodResolver::is_compatible(cur, &elemType);
        if (cmp.is_some()) {
            print("%s", cmp.get().cstr());
            let msg = Fmt::format("array element type mismatch, expecting: {} got: {}", elemType.print().str(), cur.type.print().str());
            self.err(node, msg.str());
        }
    }
    return RType::new(Type::Array{Box::new(elemType), list.len() as i32});
  }
  
  func visit_as(self, node: Expr*, lhs: Expr*, type: Type*): RType{
    let left = self.visit(lhs);
    let right = self.visit(type);
    //prim->prim
    if (left.type.is_prim() && right.type.is_prim()) {
        return right;
    }
    //derived->base
    if (left.targetDecl.is_some() && left.targetDecl.unwrap().base.is_some()) {
        let cur = left.targetDecl;
        while (cur.is_some() && cur.unwrap().base.is_some()) {
            let bs = cur.unwrap().base.get().print();
            bs.append("*");
            if (bs.eq(right.type.print().str())) return right;
            cur = self.visit(cur.unwrap().base.get()).targetDecl;
        }
    }
    if (right.type.is_pointer()) {
        return right;
    }
    if (left.type.is_pointer() && right.type.print().eq("u64")) {
        return RType::new("u64");
    }
    self.err(node, "invalid as expr");
    panic("");
  }

  func visit_is(self, node: Expr*, lhs: Expr*, rhs: Expr*): RType{
    let rt = self.visit(lhs);
    let decl1 = &rt.targetDecl;
    if (decl1.is_none() || !(decl1.unwrap() is Decl::Enum)) {
        self.err(node, Fmt::format("lhs of is expr is not enum: {}",rt.type.print().str()).str());
    }
    let rt2 = self.visit(rhs);
    let decl2 = &rt2.targetDecl;
    if (!decl1.unwrap().type.print().eq(decl2.unwrap().type.print().str())) {
        self.err(node, Fmt::format("rhs is not same type with lhs {}", decl2.unwrap().type.print().str()).str());
    }
    if let Expr::Type(ty*) = (rhs){
        findVariant(decl1.unwrap(), ty.name());
    }
    return RType::new("bool");
  }

  func visit_lit(self, lit: Literal*): RType{
    let kind = &lit.kind;
    let value = lit.val.clone();
    if(lit.suffix.is_some()){
      if(i64::parse(value.str()) > max_for(lit.suffix.get())){
        self.err("literal out of range");
      }
      return self.visit(lit.suffix.get());
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
    panic("lit");
  }

  func visit(self, node: Expr*): RType{
    let id = node.id;
    if(id == -1) panic("id");
    if(self.cache.contains(&node.id)){
      //print("cached %d, %s\n", node.id, node.print().cstr());
      return self.cache.get_ptr(&node.id).unwrap().clone();
    }
    //print("visit %d, %s\n", node.id, node.print().cstr());
    let res = self.visit_nc(node);
    self.cache.add(node.id, res);
    return res.clone();
  }
  
  func visit_nc(self, node: Expr*): RType{
    if let Expr::Lit(lit*)=(node){
      return self.visit_lit(lit);
    }else if let Expr::Type(type*) = (node){
      return self.visit(type);
    }else if let Expr::Infix(op*, lhs*, rhs*) = (node){
      return self.visit_infix(node, op, lhs.get(), rhs.get());
    }else if let Expr::Call(call*) = (node){
      return self.visit(node, call);
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
      self.err(node, Fmt::format("unknown identifier: {}", name.str()).str());
    }else if let Expr::Unary(op*, ebox*) = (node){
      return self.visit_unary(node, op, ebox.get());
    }else if let Expr::Par(expr*) = (node){
      return self.visit(expr.get());
    }else if let Expr::Access(scope*,name*) = (node){
      return self.visit_access(node, scope.get(), name);
    }else if let Expr::ArrAccess(aa*) = (node){
      return self.visit_arr_access(node, aa);
    }else if let Expr::Array(list*, size*) = (node){
      return self.visit_array(node, list, size);
    }else if let Expr::Obj(type*,args*) = (node){
      return self.visit_obj(node, type, args);
    }else if let Expr::As(lhs*, type*) = (node){
      return self.visit_as(node, lhs.get(), type);
    }else if let Expr::Is(lhs*, rhs*) = (node){
      return self.visit_is(node, lhs.get(), rhs.get());
    }
    panic("visit expr '%s'", node.print().cstr());
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

//statements-------------------------------------
impl Resolver{
  func visit(self, node: Stmt*){
    if let Stmt::Expr(e*) = (node){
      self.visit(e);
      return;
    }else if let Stmt::Block(b*) = (node){
      self.visit(b);
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
      if(!self.is_condition(e)){
        panic("assert expr is not bool: %s", e.print().cstr());
      }
      return;
    }else if let Stmt::For(f*) = (node){
      self.newScope();
      if(f.v.is_some()){
        self.visit(f.v.get());
      }
      if(f.e.is_some()){
        if (!self.isCondition(f.e.get())) {
            self.err(f.e.get(), "for statement expr is not a bool");
        }
      }
      for (let i=0;i<f.u.len();++i) {
        self.visit(f.u.get_ptr(i));
      }
      self.inLoop+=1;
      self.visit(f.body.get());
      self.inLoop-=1;
      self.dropScope();
      return;
    }else if let Stmt::If(is*) = (node){
      self.visit(node, is);
      return;
    }else if let Stmt::IfLet(is*) = (node){
      self.visit(node, is);
      return;
    }else if let Stmt::While(e*,b*) = (node){
      self.visit_while(node, e, b);
      return;
    }
    else if let Stmt::Continue = (node){
      if (self.inLoop == 0) {
        self.err(node, "continue in outside of loop");
      }
      return;
    }else if let Stmt::Break = (node){
      if (self.inLoop == 0) {
        self.err(node, "break in outside of loop");
      }
      return;
    }
    panic("visit stmt %s", node.print().cstr());
  }
  
  func visit_while(self, node: Stmt*, e: Expr*, b: Block*){
    if (!self.isCondition(e)) {
        self.err(node, "while statement expr is not a bool");
    }
    ++self.inLoop;
    self.newScope();
    self.visit(b);
    --self.inLoop;
    self.dropScope();
  }
  
  func visit(self, node: Stmt*, is: IfStmt*){
    if (!self.isCondition(&is.e)) {
        self.err(&is.e, "if condition is not a boolean");
    }
    self.newScope();
    self.visit(is.then.get());
    self.dropScope();
    if (is.els.is_some()) {
        self.newScope();
        self.visit(is.els.get().get());
        self.dropScope();
    }
  }

  func visit(self, node: Stmt*, is: IfLet*){
    //check lhs
    let rt = self.visit(&is.ty);
    if (rt.targetDecl.is_none() || !rt.targetDecl.unwrap().is_enum()) {
        let msg = Fmt::format("if let type is not enum: {}", is.ty.print().str());
        self.err(node, msg.str());
    }
    //check rhs
    let rhs = self.visit(&is.rhs);
    if (rhs.targetDecl.is_none() || !rhs.targetDecl.unwrap().is_enum()) {
      let msg = Fmt::format("if let rhs is not enum: {}", rhs.type.print().str());
      self.err(node, msg.str());
    }
    //match variant
    let decl = rt.targetDecl.unwrap();
    let index = Resolver::findVariant(decl, is.ty.name());
    let variant = decl.get_variants().get_ptr(index);
    if (variant.fields.len() != is.args.len()) {
        let msg = Fmt::format("if let args size mismatch got:{} expected: {}", i64::print(is.args.len()).str(), i64::print(variant.fields.len()).str());
        self.err(node, msg.str());
    }
    //init arg variables
    self.newScope();
    for (let i=0;i < is.args.len();++i) {
        let arg = is.args.get_ptr(i);
        let field = variant.fields.get_ptr(i);
        let ty = field.type;
        if (arg.is_ptr) {
            ty = field.type.toPtr();
        } 
        self.addScope(arg.name.clone(), ty, false);
        self.cache.add(arg.id, RType::new(ty));
    }
    self.visit(is.then.get());
    self.dropScope();
    if (is.els.is_some()) {
        self.newScope();
        self.visit(is.els.get().get());
        self.dropScope();
    }
  }
  
  func isCondition(self, e: Expr*): bool{
    let rt = self.visit(e);
    return rt.type.print().eq("bool");
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