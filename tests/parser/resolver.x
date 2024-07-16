import parser/parser
import parser/lexer
import parser/ast
import parser/printer
import parser/method_resolver
import parser/compiler_helper
import parser/utils
import parser/token
import parser/copier
import parser/derive
import parser/ownership
import std/map
import std/libc

static verbose_method: bool = false;

func verbose_stmt(): bool{
  return false;
}

struct Context{
  map: Map<String, Box<Resolver>>;
  root: String;
  prelude: List<String>;
  out_dir: String;
  verbose: bool;
  single_mode: bool;
  stack_trace: bool;
}
impl Context{
  func new(src_dir: String, out_dir: String): Context{
    let arr = ["box", "list", "str", "string", "option", "ops", "libc", "io", "map", "rt"];
    let pre = List<String>::new(arr.len());
    for(let i = 0;i < arr.len();++i){
      pre.add(arr[i].str());
    }
    return Context{map: Map<String, Box<Resolver>>::new(),
       root: src_dir,
       prelude: pre,
       out_dir: out_dir,
       verbose: true,
       single_mode: true,
       stack_trace: false
    };
  }
}

impl Drop for Context{
  func drop(*self){
    //print("Context::drop\n");
    self.map.drop();
    self.root.drop();
    self.prelude.drop();
    self.out_dir.drop();
  }
}

struct Scope{
  list: List<VarHolder>;
}

#derive(Debug)
struct VarHolder{
  name: String;
  type: Type;
  prm: bool;
  id: i32;
}
impl VarHolder{
  func new(name: String, type: Type, prm: bool, id: i32): VarHolder{
    return VarHolder{name: name, type: type, prm: prm, id: id};
  }
}
impl Clone for VarHolder{
  func clone(self): VarHolder{
    return VarHolder{
      name: self.name.clone(),
      type: self.type.clone(),
      prm: self.prm,
      id: self.id
    };
  }
}

struct FormatInfo {
  block: Block;
  unwrap_mc: Option<Expr>;
}

struct GlobalInfo{
  name: String;
  rt: RType;
  path: String;
}

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
  generated_methods: List<Box<Method>>;
  inLoop: i32;
  used_types: List<RType>;
  generated_decl: List<Box<Decl>>;
  format_map: Map<i32, FormatInfo>;
  glob_map: List<GlobalInfo>;//external glob name->local rt for it, (cloned)
  drop_map: Map<String, Desc>;
}
impl Drop for Resolver{
  func drop(*self){
    //print("Resolver::drop {}\n", &self.unit.path);
    self.unit.drop();
    self.typeMap.drop();
    self.cache.drop();
    self.scopes.drop();
    self.used_methods.drop();
    self.generated_methods.drop();
    self.used_types.drop();
    self.generated_decl.drop();
    self.format_map.drop();
    self.glob_map.drop();
    self.drop_map.drop();
  }
}

#derive(Debug)
enum RtKind{
  None,//prim, ptr
  Method,//free method in items
  MethodImpl(idx2: i32),//impl method
  MethodGen,//generic method in resolver
  MethodExtern(idx2: i32),
  Decl,//decl in items
  DeclGen,//generic decl in resolver
  Trait//trait in items
}
impl RtKind{
  func is_method(self): bool{
    return self is RtKind::Method || self is RtKind::MethodImpl || self is RtKind::MethodGen || self is RtKind::MethodExtern;
  }
  func is_decl(self): bool{
    return self is RtKind::Decl || self is RtKind::DeclGen;
  }
  func is_trait(self): bool{
    return self is RtKind::Trait;
  }
}

#derive(Debug)
struct Desc{
  kind: RtKind;
  path: String;
  idx: i32;
}
impl Desc{
  func new(): Desc{
    return Desc{
      kind: RtKind::None,
      path: "".str(),
      idx: -1
    };
  }
  func clone(self): Desc{
    return Desc{
      kind: self.kind,
      path: self.path.clone(),
      idx: self.idx
    };
  }
}

#derive(Debug)
struct RType{
  type: Type;
  value: Option<String>;
  vh: Option<VarHolder>;
  desc: Desc;
  method_desc: Option<Desc>;
}
impl RType{
  func new(s: str): RType{
    return RType::new(Type::new(s.str()));
  }
  func new(typ: Type): RType{
    let res = RType{typ, Option<String>::None, Option<VarHolder>::None, Desc::new(), Option<Desc>::new()};
    return res;
  }
  func clone(self): RType{
    return RType{type: self.type.clone(),
      value: self.value.clone(),
      vh: self.vh.clone(),
      desc: self.desc.clone(),
      method_desc: self.method_desc.clone()
    };
  }
  func unwrap(*self): Type{
    let res = self.type;
    self.value.drop();
    self.vh.drop();
    self.desc.drop();
    self.method_desc.drop();
    return res;
  }
  func is_decl(self): bool{
    return self.desc.kind.is_decl();
  }
  func is_trait(self): bool{
    return self.desc.kind.is_trait();
  }
  func is_method(self): bool{
    if(self.method_desc.is_none()){
      return false;
    }
    return self.method_desc.get().kind.is_method();
  }
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

impl Context{
  func create_resolver(self, path: String*): Resolver*{
    let res = self.map.get_ptr(path);
    if(res.is_some()){
      return res.unwrap().get();
    }
    let r = Resolver::new(path.clone(), self);
    let pair = self.map.add(path.clone(), Box::new(r));
    return pair.b.get();
  }
  func create_resolver(self, path: str): Resolver*{
    let path2 = path.str();
    let res = self.create_resolver(&path2);
    Drop::drop(path2);
    return res;
  }
  func get_path(self, is: ImportStmt*): String{
    let path = self.root.clone();
    for(let i = 0;i < is.list.len();++i){
      let part: String* = is.list.get_ptr(i);
      path.append("/");
      path.append(part.str());
    }
    path.append(".x");
    return path;
  }
  func get_resolver(self, is: ImportStmt*): Resolver*{
    let path = self.get_path(is);
    return self.create_resolver(&path);
  }
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

func join(list: List<String>*, sep: str): String{
  let s = String::new();
  for(let i = 0;i < list.len();++i){
    let path = list.get_ptr(i);
    s.append(path.str());
  }
  return s;
}

func has(arr: List<ImportStmt>*, is: ImportStmt*): bool{
  for (let i = 0;i < arr.len();++i) {
      let i1 = arr.get_ptr(i);
      let s1: String = join(&i1.list, "/");
      let s2: String = join(&is.list, "/");
      if (s1.eq(&s2)) {
          Drop::drop(s1);
          Drop::drop(s2);
          return true;
      }
      Drop::drop(s1);
      Drop::drop(s2);
  }
  return false;
}

func dumpp(r: Resolver*){
  r.dump();
}

static print_unit: bool = false;

impl Resolver{
  func new(path: String, ctx: Context*): Resolver{
    //print("Resolver::new {}\n", &path);
    let parser = Parser::from_path(path);
    let unit = parser.parse_unit();
    Drop::drop(parser);
    if(print_unit){
      print("print_unit\n");
      print("unit={}\n", unit);
    }
    
    let res = Resolver{unit: unit,
      is_resolved: false,
      is_init: false,
      typeMap: Map<String, RType>::new(),
      cache: Map<i32, RType>::new(),
      curMethod: Option<Method*>::None,
      curImpl: Option<Impl*>::None,
      scopes: List<Scope>::new(),
      ctx: ctx,
      used_methods: List<Method*>::new(),
      generated_methods: List<Box<Method>>::new(),
      inLoop: 0,
      used_types: List<RType>::new(),
      generated_decl: List<Box<Decl>>::new(),
      //generated_impl: List<Impl>::new(),
      format_map: Map<i32, FormatInfo>::new(),
      glob_map: List<GlobalInfo>::new(),
      drop_map: Map<String, Desc>::new()
    };
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
  func addScope(self, name: String, type: Type, prm: bool, id: i32){
    for(let i=0;i<self.scopes.len();++i){
      let s = self.scopes.get_ptr(i);
      if(s.find(&name).is_some()){
        panic("variable {} already exists\n", name);
      }
    }
    let scope = self.scopes.last();
    scope.list.add(VarHolder::new(name, type, prm, id));
  }
 
  func get_unit(self, path: String*): Unit*{
    let r = self.ctx.create_resolver(path);
    return &r.unit;
  }

  func getPath(self, is: ImportStmt*): String {
    return format("{}/{}.x", self.ctx.root, join(&is.list, "/"));
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
      let path = format("std/{}.x", pre);
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
            imports.add(is.clone());
        }
    }
    if (self.curMethod.is_some() && !self.curMethod.unwrap().type_params.empty()) {
        let tmp = &self.get_unit(&self.curMethod.unwrap().path).imports;
        for (let i = 0;i < tmp.len();++i) {
            let is = tmp.get_ptr(i);
            if (has(&imports, is)) continue;
            //skip self being cycle
            let iss = self.getPath(is);
            if (self.unit.path.eq(&iss)) continue;
            imports.add(is.clone());
        }
    }
    return imports;
}
  
  func resolve_all(self){
    if(self.is_resolved) return;
    //print("resolve_all {}\n", self.unit.path);
    self.is_resolved = true;
    self.init();
    self.init_globals();
    for(let i = 0;i < self.unit.items.len();++i){
      let item = self.unit.items.get_ptr(i);
      self.visit_item(item);
    }
    //todo these would generate more methods, whose are not visited
    for(let j = 0;j < self.generated_methods.len();++j){
      let gm = self.generated_methods.get_ptr(j).get();
      self.visit_method(gm);
    }
  }
  
  func init_globals(self){
    self.newScope();//globals
    for (let i = 0;i < self.unit.globals.len();++i) {
        let g = self.unit.globals.get_ptr(i);
        let rhs: RType = self.visit(&g.expr);
        if (g.type.is_some()) {
            let type = self.getType(g.type.get());
            //todo check
            let err_opt = MethodResolver::is_compatible(&rhs.type, &type);
            if (err_opt.is_some()) {
                let msg = format("variable type mismatch {}\nexpected: {} got {}\n{}'", g.name, type,rhs.type, err_opt.get());
                self.err(msg);
            }
        }
        self.addScope(g.name.clone(), rhs.type.clone(), false, g.id);
    }
  }

  func dump_types(self){
    print("{} types\n", self.typeMap.len());
    for(let i = 0;i < self.typeMap.len();++i){
      let pair = self.typeMap.get_pair_idx(i).unwrap();
      print("{} -> {}\n", pair.a, pair.b.type);
    }
  }

  func dump(self){
    //print("---dump---");
    print("scope count {}\n", self.scopes.len());
    for(let i = 0;i < self.scopes.len();++i){
      let scope = self.scopes.get_ptr(i);
      print("scope {} has {} vars\n", i + 1, scope.list.len());
      for(let j = 0;j < scope.list.len();++j){
        let vh = scope.list.get_ptr(j);
        print("{}:{}\n", vh.name, vh.type);
      }
    }
  }

  func addType(self, name: String, res: RType){
    //print("addType {}=", name);
    //print("{}\n", &res);
    self.typeMap.add(name, res);
  }
  
  func init(self){
    if(self.is_init) return;
    if(self.ctx.verbose){
      //print("Resolver::init {}\n", &self.unit.path);
    }
    self.is_init = true;

    for(let i = 0;i < self.unit.items.len();++i){
      let it = self.unit.items.get_ptr(i);
      //Fmt::str(it).dump();
      if let Item::Decl(decl*) = (it){
        let ty = decl.type.clone();
        let res = RType::new(ty);
        res.desc = Desc{RtKind::Decl, self.unit.path.clone(), i};
        self.addType(decl.type.name().clone(), res);
      }else if let Item::Trait(tr*) = (it){
        let res = RType::new(tr.type.clone());
        res.desc = Desc{RtKind::Trait, self.unit.path.clone(), i};
        self.addType(tr.type.name().clone(), res);
      }else if let Item::Impl(imp*) = (it){
        //pass
      }else if let Item::Type(name*, rhs*) = (it){
        let res = self.visit_type(rhs);
        self.addType(name.clone(), res);
      }
    }
    //derives
    let newItems = List<Item>::new();
    for(let i = 0;i < self.unit.items.len();++i){
      let it = self.unit.items.get_ptr(i);
      if let Item::Decl(decl*) = (it){
        self.handle_derive(decl, &newItems);
      }
    }
    self.unit.items.add_list(newItems);
  }
  func handle_derive(self, decl: Decl*, newItems: List<Item>*){
    //derive
    for(let j = 0;j < decl.derives.len();++j){
      let der: Type* = decl.derives.get_ptr(j);
      let der_str = der.print();
      if(der_str.eq("Drop")){
        self.err("drop is auto impl");
      }
      let imp = generate_derive(decl, &self.unit, der_str.str());
      newItems.add(Item::Impl{imp});
    }
    let helper = DropHelper{self};
    //improve decl.is_generic, this way all generic types derives drop but dont need to
    if (!DropHelper::has_drop_impl(decl, self)) {
      if(decl.is_generic || helper.is_drop_decl(decl)){
        newItems.add(Item::Impl{generate_derive(decl, &self.unit, "Drop")});
      }
    }
  }

  func err(self, msg: str){
    if(self.curMethod.is_some()){
      let str: String = printMethod(self.curMethod.unwrap());
      print("{}\n", str);
      Drop::drop(str);
    }
    panic("{}\n", msg);
  }
  func err(self, msg: String){
    self.err(msg.str());
    Drop::drop(msg);
  }
  func err(self, node: Expr*, msg: str){
    let path = &self.unit.path;
    if(self.curMethod.is_some()){
      path = &self.curMethod.unwrap().path;
    }
    let str = format("{}:{}\n{} {}", path, node.line, msg, node);
    panic("{}\n", str);
  }
  func err(self, node: Expr*, msg: String){
    self.err(node, msg.str());
    Drop::drop(msg);
  }
  func err(self, node: Stmt*, msg: str){
    let str = format("{}\n{} {}", self.unit.path, msg, node);
    self.err(str);
  }
  func err(self, node: Stmt*, msg: String){
    self.err(node, msg.str());
  }
  func err(self, line: i32, msg: String){
    let path = &self.unit.path;
    if(self.curMethod.is_some()){
      path = &self.curMethod.unwrap().path;
    }
    let str = format("{}:{}\n{}", path, line, msg);
    panic("{}\n", str);
  }

  func getType(self, e: Type*): Type{
    let rt = self.visit_type(e);
    let res = rt.type.clone();
    rt.drop();
    return res;
  }
  func getType(self, e: Expr*): Type{
    let rt = self.visit(e);
    let res = rt.type.clone();
    rt.drop();
    return res;
  }
  func getType(self, f: Fragment*): Type{
    let rt = self.visit(f);
    let res = rt.type.clone();
    rt.drop();
    return res;
  }
  
  func get_decl(self, ty: Type*): Option<Decl*>{
    let rt = self.visit_type(ty);
    return self.get_decl(&rt);
  }
  func get_decl(self, rt: RType*): Option<Decl*>{
    if(rt.type.is_pointer()){
      return self.get_decl(rt.type.unwrap_ptr());
    }
    if(rt.desc.kind is RtKind::Trait){
      return Option<Decl*>::new();
    }
    if(rt.desc.kind is RtKind::Decl){
      let resolver = self.ctx.create_resolver(&rt.desc.path);
      let unit = &resolver.unit;
      let item = unit.items.get_ptr(rt.desc.idx);
      if let Item::Decl(decl*) = (item){
        return Option::new(decl);
      }
    }
    if(rt.desc.kind is RtKind::DeclGen){
      let resolver = self.ctx.create_resolver(&rt.desc.path);
      if(resolver.generated_decl.in_index(rt.desc.idx)){
        let decl = resolver.generated_decl.get_ptr(rt.desc.idx).get();
        if(!decl.type.eq(rt.type.unwrap_ptr().print().str())){
          panic("get_decl err {}={}", rt.type, rt.desc);
        }
        return Option::new(decl);
      }
    }
    if(rt.desc.kind is RtKind::None || rt.desc.kind is RtKind::MethodImpl || rt.desc.kind is RtKind::MethodGen){
      return Option<Decl*>::new();
    }
    panic("get_decl() {}={}", rt.type, rt.desc);
  }
  func get_trait(self, rt: RType*): Option<Trait*>{
    if(rt.desc.kind is RtKind::Trait){
      let resolver = self.ctx.create_resolver(&rt.desc.path);
      let unit = &resolver.unit;
      let item = unit.items.get_ptr(rt.desc.idx);
      if let Item::Trait(tr*) = (item){
        return Option::new(tr);
      }
    }
    panic("get_trait {}={}", rt.type, rt.desc);
  }
  func get_method(self, rt: RType*): Option<Method*>{
    if(rt.method_desc.is_none()){
      return Option<Method*>::new();
    }
    return self.get_method(rt.method_desc.get(), &rt.type);
  }
  func get_method(self, desc: Desc*, type: Type*): Option<Method*>{
    if(desc.kind is RtKind::Method){
      let resolver = self.ctx.create_resolver(&desc.path);
      let unit = &resolver.unit;
      let item = unit.items.get_ptr(desc.idx);
      if let Item::Method(m*) = (item){
        return Option::new(m);
      }
    }
    if let RtKind::MethodImpl(idx2) = (desc.kind){
      let resolver = self.ctx.create_resolver(&desc.path);
      let unit = &resolver.unit;
      let item = unit.items.get_ptr(desc.idx);
      if let Item::Impl(imp*) = (item){
        let m = imp.methods.get_ptr(idx2);
        return Option::new(m);
      }
    }
    if let RtKind::MethodGen = (desc.kind){
      let resolver = self.ctx.create_resolver(&desc.path);
      let m = resolver.generated_methods.get_ptr(desc.idx);
      return Option::new(m.get());
    }
    if let RtKind::MethodExtern(idx2) = (desc.kind){
      let resolver = self.ctx.create_resolver(&desc.path);
      let unit = &resolver.unit;
      let item = unit.items.get_ptr(desc.idx);
      if let Item::Extern(methods*) = (item){
        let m = methods.get_ptr(idx2);
        return Option::new(m);
      }
    }
    panic("get_method {}={}", type, desc);
  }

  func visit_item(self, node: Item*){
    if let Item::Method(m*) = (node){
      self.visit_method(m);
    }else if let Item::Type(name*, rhs*) = (node){
      //pass
    }else if let Item::Impl(imp*) = (node){
      self.visit_impl(imp);
    }else if let Item::Decl(decl*) = (node){
      if let Decl::Struct(fields*) = (decl){
        self.visit_decl(decl, fields);
      }else if let Decl::Enum(variants*) = (decl){
        self.visit_enum(decl, variants);
      }
    }else if let Item::Trait(tr*) = (node){
    }else if let Item::Extern(methods*) = (node){
      for(let i = 0;i < methods.len();++i){
        let m = methods.get_ptr(i);
        if(m.is_generic) continue;
        self.visit_method(m);
      }
    }
    else{
      Fmt::str(node).dump();
      panic("visitItem");
    }
  }

  func is_cyclic(self, type: Type*, target: Type*): bool{
    //print("is_cyclic {} -> {}\n", type0, target);
    if (type.is_pointer()) return false;
    if (type.is_array()) {
        return self.is_cyclic(type.elem(), target);
    }
    if (type.is_slice()) return false;
    if (type.eq(target.print().str())) {
        return true;
    }
    let rt = self.visit_type(type);
    if (!is_struct(&rt.type)) return false;
    let decl = self.get_decl(&rt).unwrap();
    Drop::drop(rt);
    if (decl.base.is_some()) {
      if(self.is_cyclic(decl.base.get(), target)){
        return true;
      }
    }
    if let Decl::Enum(variants*)=(decl) {
      for (let i = 0;i < variants.len();++i) {
        let ev = variants.get_ptr(i);
        for (let j = 0;j < ev.fields.len();++j) {
          let f1 = ev.fields.get_ptr(j);
          if (self.is_cyclic(&f1.type, target)) {
              return true;
          }
        }
      }
    } else if let Decl::Struct(fields*)=(decl){
      for (let j = 0;j < fields.len();++j) {
        let f2: FieldDecl* = fields.get_ptr(j);
        if (self.is_cyclic(&f2.type, target)) {
            return true;
        }
      }
    }
    return false;
  }

  func is_valid_field(self, fd: FieldDecl*, node: Decl*, base_fields: Option<List<FieldDecl>*>){
    if(base_fields.is_some()){
      let base_f = base_fields.unwrap();
      for(let j = 0;j < base_f.len();++j){
        let bf = base_f.get_ptr(j);
        if(bf.name.eq(&fd.name)){
          self.err(node.line, format("field name '{}' already declared in base", fd.name));
        }
      }
    }
    self.visit_type(&fd.type);
    if(self.is_cyclic(&fd.type, &node.type)){
      self.err(format("cyclic type {}", node.type));
    }
  }

  func visit_decl(self, node: Decl*, fields: List<FieldDecl>*){
    if(node.is_generic) return;
    node.is_resolved = true;
    let base_fields = Option<List<FieldDecl>*>::new();
    if(node.base.is_some()){
      let base_rt = self.visit_type(node.base.get());
      let base_decl = self.get_decl(&base_rt).unwrap();
      if(base_decl.is_struct()){
        base_fields = Option::new(base_decl.get_fields());
      }
    }
    for(let i = 0;i < fields.len();++i){
      let fd = fields.get_ptr(i);
      self.is_valid_field(fd, node, base_fields);
    }
  }
  func visit_enum(self, node: Decl*, vars: List<Variant>*){
    if(node.is_generic) return;
    node.is_resolved = true;
    let base_fields = Option<List<FieldDecl>*>::new();
    if(node.base.is_some()){
      let base_rt = self.visit_type(node.base.get());
      let base_decl = self.get_decl(&base_rt).unwrap();
      if(base_decl.is_struct()){
        base_fields = Option::new(base_decl.get_fields());
      }
    }
    for(let i = 0;i < vars.len();++i){
      let ev = vars.get_ptr(i);
      for(let j = 0;j < ev.fields.len();++j){
        let fd = ev.fields.get_ptr(j);
        self.is_valid_field(fd, node, base_fields);
      }
    }
  }

  func visit_impl(self, imp: Impl*){
    if(!imp.info.type_params.empty()){
      //generic
      return;
    }
    self.curImpl = Option::new(imp);
    //resolve non generic type args
    if(imp.info.trait_name.is_some()){
      //todo
      let required = Map<String, Method*>::new();
      let trait_rt = self.visit_type(imp.info.trait_name.get());
      let trait_decl = self.get_trait(&trait_rt).unwrap();
      for(let i = 0;i < trait_decl.methods.len();++i){
        let m = trait_decl.methods.get_ptr(i);
        if(m.body.is_none()){
          let mangled = mangle2(m, &imp.info.type);
          required.add(mangled, m);
        }
      }
      for(let i = 0;i < imp.methods.len();++i){
        let m = imp.methods.get_ptr(i);
        if(!m.type_params.empty()) continue;
        self.visit_method(m);
        let mangled = mangle2(m, &imp.info.type);
        let idx = required.indexOf(&mangled);
        if(idx != -1){
          required.remove_idx(idx);
        }
      }
      if(!required.empty()){
        let msg = String::new();
        for(let i = 0;i < required.len();++i){
          let p = required.get_pair_idx(i).unwrap();
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
        if(!m.type_params.empty()) continue;
        self.visit_method(m);
      }
    }
    self.curImpl = Option<Impl*>::None;
  }

  func visit_method(self, node: Method*){
    if(verbose_method){
      print("visit_method {} {} generic: {}\n", printMethod(node), self.unit.path, node.is_generic);
    }
    if(node.is_generic){
      return;
    }
    self.curMethod = Option::new(node);
    let res = self.visit_type(&node.type);
    self.newScope();
    if(node.self.is_some()){
      let self_prm: Param* = node.self.get();
      self.visit_type(&self_prm.type);
      self.addScope(self_prm.name.clone(), self_prm.type.clone(), true, self_prm.id);
    }
    for(let i = 0;i < node.params.len();++i){
      let prm = node.params.get_ptr(i);
      self.visit_type(&prm.type);
      self.addScope(prm.name.clone(), prm.type.clone(), true, prm.id);
    }
    if(node.body.is_some()){
      self.visit(node.body.get());
      let exit = Exit::get_exit_type(node.body.get());
      if (!node.type.is_void() && !exit.is_exit()) {
        let msg = String::new("non void function ");
        msg.append(printMethod(node).str());
        msg.append(" must return a value");
        self.err(msg.str());
      }
    }
    self.dropScope();
    self.curMethod = Option<Method*>::None;
  }

  func unwrap_mc(expr: Expr*): Call*{
    if let Expr::Call(mc*) = (expr){
        return mc;
    }
    panic("unwrap_mc {}", expr);
  }

  func handle_drop_method(self, rt: RType*, decl: Decl*){
    let helper = DropHelper{self};
    if(!helper.is_drop_decl(decl)){
      return;
    }
    if(decl.type.get_args().empty()){
      //extern drop
      return;
    }
    //generic drop, local or extern
    let drop_impl = helper.find_drop_impl(decl);
    let method = drop_impl.methods.get_ptr(0);
    let drop_expr = parse_expr(format("{}::drop()", &decl.type), &self.unit, decl.line);
    let mc = unwrap_mc(&drop_expr);
    let sig = Signature::new("drop".str());
    sig.scope = Option::new(rt.clone());
    sig.args.add(decl.type.clone());
    sig.mc = Option::new(mc);
    sig.r = Option::new(self);
    let mr = MethodResolver::new(self);
    let map = Map<String, Type>::new();
    let generic_type = &method.parent.as_impl().type;
    for(let i = 0;i < decl.type.get_args().len();++i){
        let tp = generic_type.get_args().get_ptr(i);
        map.add(tp.print(), decl.type.get_args().get_ptr(i).clone());
    }
    let pair = mr.generateMethod(&map, method, &sig);
    //method = pair.a;
    self.drop_map.add(decl.type.print().clone(), pair.b.clone());
    //print("handle_drop_method {}\n", rt.type);
  }

  func add_used_decl(self, decl: Decl*){
    for(let i = 0;i < self.used_types.len();++i){
      let used: RType* = self.used_types.get_ptr(i);
      if(used.type.eq(&decl.type)){
        return;
      }
    }
    //print("add_used_decl {}\n", decl.type);
    let rt = self.visit_type(&decl.type);
    //gen drop method
    self.handle_drop_method(&rt, decl);
    self.used_types.add(rt);
    if(decl.base.is_some()){
      self.visit_type(decl.base.get());
    }
    if(decl is Decl::Struct){
      let fields = decl.get_fields();
      for(let i = 0;i < fields.len();++i){
        let fd = fields.get_ptr(i);
        self.visit_type(&fd.type);
      }
    }else{
      let variants = decl.get_variants();
      for(let i = 0;i < variants.len();++i){
        let ev = variants.get_ptr(i);
        for(let j = 0;j < ev.fields.len();++j){
          let f = ev.fields.get_ptr(j);
          self.visit_type(&f.type);
        }
      }
    }
  }
  
  func addUsed(self, m: Method*){
    let mng = mangle(m);
    for(let i = 0;i < self.used_methods.len();++i){
      let prev = *self.used_methods.get_ptr(i);
      if(mangle(prev).eq(mng.str())) return;
    }
    self.used_methods.add(m);
    let last = *self.used_methods.last();
    Fmt::str(last);
  }
  
  func visit_field(self, node: FieldDecl*): RType{
    return self.visit_type(&node.type);
  }
}


//expressions-------------------------------------
impl Resolver{
  func is_condition(self, e: Expr*): bool{
    let tmp = self.visit(e);
    return tmp.type.print().eq("bool");
  }

  func clone_op(op: Option<Decl*>*): Option<Decl*>{
    if(op.is_none()) return Option<Decl*>::new();
    return Option<Decl*>::new(*op.get());
  }
  func visit_type(self, node: Type*): RType{
    let id = Node::new(0);
    let expr = Expr::Type{.id, node.clone()};
    let res = self.visit_type(&expr, node);
    Drop::drop(expr);
    return res;
  }

  func visit_type(self, expr: Expr*, node: Type*): RType{
    let str = node.print();
    let res = self.visit_type_str(expr, node, &str);
    Drop::drop(str);
    return res;
  }

  func visit_type_str(self, expr: Expr*, node: Type*, str: String*): RType{
    let cached = self.typeMap.get_ptr(str);
    if(cached.is_some()){
      return cached.unwrap().clone();
    }
    if(node.is_prim() || node.is_void()){
      let res = RType::new(str.str());
      self.addType(str.clone(), res.clone());
      return res;
    }
    if(node.is_pointer()){
      let inner = node.unwrap_ptr();
      let res = self.visit_type(inner);
      let ptr = res.type.clone().toPtr();
      res.type = ptr;
      return res;
    }
    if(node.is_slice()){
      let inner = node.elem();
      let elem = self.visit_type(inner);
      return RType::new(Type::Slice{.Node::new(-1, node.line), Box::new(elem.type.clone())});      
    }
    if let Type::Array(inner*, size) = (node){
      let elem = self.visit_type(inner.get());
      return RType::new(Type::Array{.Node::new(-1, node.line), Box::new(elem.type.clone()), size});      
    }
    if (str.eq("Self") && !self.curMethod.unwrap().parent.is_none()) {
      let imp = self.curMethod.unwrap().parent.as_impl();
      return self.visit_type(&imp.type);
    }
    let simple: Simple* = node.as_simple();
    if (simple.scope.is_some()) {
      //simple enum variant
      let scope = self.visit_type(simple.scope.get());
      let decl = self.get_decl(&scope).unwrap();
      if (!(decl is Decl::Enum)) {
          panic("type scope is not enum: {}", str);
      }
      findVariant(decl, &simple.name);
      let ds = decl.type.print();
      let res = self.getTypeCached(&ds);
      self.addType(str.clone(), res.clone());
      return res;
    }
    let res = self.visit_type2(expr, simple, str);
    //print("visit_type2 {} -> {}\n", node, res.desc);
    return res;
  }

  func find_type(self, expr: Expr*, simple: Simple*): RType{
    let name = &simple.name;
    if (self.typeMap.contains(name)) {
      let rt: RType* = self.typeMap.get_ptr(name).unwrap();
      return rt.clone();
    }
    let imp_result: Option<RType> = self.find_imports(simple, name);
    if(imp_result.is_none()){
      self.err(expr, "couldn't find type");
    }
    let tmp: RType = imp_result.unwrap();
    return tmp;
  }

  func visit_type2(self, expr: Expr*, simple: Simple*, str: String*): RType{
    let target_rt: RType = self.find_type(expr, simple);
    if(!target_rt.is_decl()){
      //add used
      return target_rt;
    }
    if (!simple.args.empty()) {
      //local gen or foreign gen, place targs, gen decl, return
    }else{
      //local gen root, foreign gen root, foreign alias; find & return
    }
    let target: Decl* = self.get_decl(&target_rt).unwrap();
    //generic
    if (simple.args.empty() || !target.is_generic) {
        //inferred later
        let res = RType::new(target.type.clone());
        res.desc = target_rt.desc.clone();
        self.addType(str.clone(), res.clone());
        target_rt.drop();
        return res;
    }
    target_rt.drop();
    if (simple.args.len() != target.type.get_args().len()) {
      self.err(expr, "type arguments size not matched");
    }
    let map = make_type_map(simple, target);
    let copier = AstCopier::new(&map);
    let decl0 = copier.visit(target);
    let decl: Decl* = self.add_generated(decl0);
    self.add_used_decl(decl);//fields may be foreign
    let res = self.getTypeCached(str);
    return res;
  }

  func add_generated(self, decl: Decl): Decl*{
    let res = self.generated_decl.add(Box::new(decl)).get();
    let rt = RType::new(res.type.clone());
    let idx = self.generated_decl.len() - 1;
    rt.desc = Desc{RtKind::DeclGen, self.unit.path.clone(), idx as i32};
    //print("add_generated {}={}\n", res.type, rt.desc);
    self.addType(res.type.print(), rt);
    return res;
  }
  //A<T1, T2>=A<B, C> -> (T1: B), (T2: C) 
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
    if(str.eq("List<u8>")){
      let aa = 10;
    }
    let arr = self.get_imports();
    for (let i = 0;i < arr.len();++i) {
      let is = arr.get_ptr(i);
      let resolver = self.ctx.get_resolver(is);
      resolver.init();
      let cached = resolver.typeMap.get_ptr(&type.name);
      if (cached.is_some()) {
        let res: RType = cached.unwrap().clone();
        let decl = self.get_decl(&res);
        if (decl.is_some() && !decl.unwrap().is_generic) {
          self.addType(str.clone(), res.clone());
          self.add_used_decl(decl.unwrap());
        }
        return Option::new(res);
      }
      //try full type
      /*let cached = resolver.typeMap.get_ptr(str);
      if (cached.is_some()) {
          let res = cached.unwrap().clone();
          res.desc.path = self.unit.path.clone();
          self.addType(str, res.clone());
          if (res.is_decl()) {
            let decl = self.get_decl(&res).unwrap();
            if (!decl.is_generic) {
                self.add_used_decl(decl);
            }
          }
          //todo trait
          return Option::new(res);
      }
      if (!type.args.empty()) {
          //generic type
          //try root type
          let cached2 = resolver.typeMap.get_ptr(&type.name);
          if (cached2.is_some() && cached2.unwrap().is_decl()){
            let res = cached2.unwrap().clone();
            res.desc.path = self.unit.path.clone();
            return Option::new(res);
          }
      }*/
    }
    arr.drop();
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
    panic("unknown variant {}::{}", decl.type, name);
  }

  func getTypeCached(self, str: String*): RType{
    let res = self.typeMap.get_ptr(str);
    if(res.is_some()){
      return res.unwrap().clone();
    }
    panic("not cached {}", str);
  }
  
  func findField(self, node: Expr*, name: String*, decl: Decl*, type: Type*): Pair<Decl*, i32>{
    let cur = decl;
    while (true) {
        if (cur is Decl::Struct) {
            let fields = cur.get_fields();
            let idx = 0;
            for (let i = 0; i < fields.len();++i) {
                let fd = fields.get_ptr(i);
                if (fd.name.eq(name)) {
                    return Pair::new(cur, idx);
                }
                ++idx;
            }
        }
        if (cur.base.is_some()) {
            let base = self.get_decl(cur.base.get());
            if(base.is_none()) break;
            cur = base.unwrap();
        } else {
            break;
        }
    }
    let msg = format("invalid field {} of {}", name, type); 
    self.err(node, msg);
    panic("");
  }
  
  func visit_access(self, node: Expr*, scope: Expr*, name: String*): RType{
    let scp = self.visit(scope);
    scp = self.visit_type(&scp.type);
    if (!scp.is_decl()) {
      let msg = format("invalid field {} of {}", name, scp.type); 
      self.err(node, msg);
    }
    let decl = self.get_decl(&scp).unwrap();
    let pair = self.findField(node, name, decl, &scp.type);
    let fd = pair.a.get_fields().get_ptr(pair.b);
    scp.drop();
    return self.visit_field(fd);
  }
  
  func fieldIndex(arr: List<FieldDecl>*, name: str, type: Type*): i32{
    for(let i=0;i<arr.len();++i){
      let fd = arr.get_ptr(i);
      if(fd.name.eq(name)){
        return i;
      }
    }
    panic("unknown field {}.{}", type, name);
  }
  
  func visit_obj(self, node: Expr*, type0: Type*, args: List<Entry>*): RType{
    let hasNamed = false;
    let hasNonNamed = false;
    let base = Option<Expr*>::new();
    for (let i = 0;i < args.len();++i) {
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
    let res = self.visit_type(type0);
    let decl = self.get_decl(&res).unwrap();
    if (decl.base.is_some() && base.is_none()) {
        self.err(node, "base class is not initialized");
    }
    if (decl.base.is_none() && base.is_some()) {
        self.err(node, "wasn't expecting base");
    }
    if (base.is_some()) {
        let base_ty = &self.visit(base.unwrap()).type;
        if (!base_ty.print().eq(decl.base.get().print().str())){
            let msg = format("invalid base class type: {} expecting {}", base_ty, decl.base.get());
            self.err(node, msg);
        }
    }
    let fields0 = Option<List<FieldDecl>*>::new();
    let type = Type::new("");
    
    if let Decl::Enum(variants*)=(decl){
        let idx = findVariant(decl, type0.name());
        let variant = variants.get_ptr(idx);
        fields0 = Option::new(&variant.fields);
        type = Type::new(decl.type.clone(), variant.name.clone());
    }else if let Decl::Struct(f*)=(decl){
        fields0 = Option::new(f);
        type = decl.type.clone();
        if (decl.is_generic) {
            //infer
            let inferred: Type = self.inferStruct(node, &decl.type, hasNamed, f, args);
            res = self.visit_type(&inferred);
            let gen_decl = self.get_decl(&res).unwrap();
            fields0 = Option::new(gen_decl.get_fields());
        }
    }
    let fields = fields0.unwrap();
    let field_idx = 0;
    let names = List<String>::new();
    for (let i = 0; i < args.len(); ++i) {
        let e: Entry* = args.get_ptr(i);
        if (e.isBase) continue;
        let prm_idx = 0;
        if (hasNamed) {
            names.add(e.name.get().clone());
            prm_idx = fieldIndex(fields, e.name.get().str(), &type);
        } else {
            prm_idx = field_idx;
            ++field_idx;
        }
        let prm = fields.get_ptr(prm_idx);
        //todo if we support unnamed fields, change this
        if (!hasNamed) {
            names.add(prm.name.clone());
        }
        let pt = self.getType(&prm.type);
        let arg = self.visit(&e.expr);
        if (MethodResolver::is_compatible(&arg.type, &pt).is_some()) {
            let f = format("field type is imcompatiple {}\n expected: {} got: {}", e.expr, pt, arg.type);
            self.err(node, f.str());
        }
    }
    //check non set fields
    for (let i = 0;i < fields.len();++i) {
        let fd = fields.get_ptr(i);
        if (!names.contains(&fd.name)) {
            let msg = format("field not set: {}", fd.name);
            self.err(node, msg);
        }
    }
    return res;
  }

  func inferStruct(self, node: Expr*, type: Type*, hasNamed: bool, fields: List<FieldDecl>*, args: List<Entry>*): Type{
    let inferMap = Map<String, Type>::new();
    let type_params: List<Type>* = type.get_args();
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
        MethodResolver::infer(&arg_type.type, target_type, &inferMap, type_params);
    }
    let res = Simple::new(type.name().clone());
    for (let i = 0;i < type_params.len();++i) {
        let tp = type_params.get_ptr(i);
        let opt = inferMap.get_ptr(tp.name());
        if (opt.is_none()) {
            self.err(node, format("can't infer type parameter: {}", tp));
        }
        res.args.add(opt.unwrap().clone());
    }
    return res.into(node.line);
  }
  
  func visit_unary(self, node: Expr*, op: String*, e: Expr*): RType{
    if(op.eq("&")){
      return self.visit_ref(node, e);
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
    if (MethodResolver::is_compatible(&t2.type, &t1.type).is_some()) {
      let msg = format("cannot assign {}={}", t1.type, t2.type);
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
    if(!lt.type.is_prim() || !rt.type.is_prim()){
      self.err(node, "infix on non prim type");
    }
    if(is_comp(op.str())){
      return RType::new("bool");
    }
    else if(op.eq("&&") || op.eq("||")){
      if (!lt.type.eq("bool")) {
        panic("infix lhs is not boolean: {}", lhs);
      }
      if (!rt.type.eq("bool")) {
        panic("infix rhs is not boolean: {}", rhs);
      }        
      return RType::new("bool");
    }else{
      return RType::new(infix_result(lt.type.print().str(), rt.type.print().str()));
    }
  }

  func visit_ref(self, node: Expr*, e: Expr*): RType{
    if(node.id == 712){
      let a = 10;
    }
    if(e is Expr::Name || e is Expr::Access || e is Expr::ArrAccess || e is Expr::Lit){
      let res = self.visit(e);
      res.type = res.type.clone().toPtr();
      return res;
    }
    self.err(node, "ref expr is not supported");
    panic("");
  }

  func visit_deref(self, node: Expr*, e: Expr*): RType{
    let inner = self.visit(e);
    if(!inner.type.is_pointer()){
      self.err(format("deref expr is not pointer: {} -> {}", node, inner.type));
    }
    inner.type = inner.type.unwrap_ptr().clone();
    return inner;
  }

  func is_special(self, mc: Call*, name: str, kind: TypeKind): bool{
    if (mc.scope.is_none() || !mc.name.eq(name) || !mc.args.empty()) {
      return false;
    }
    let scope = self.getType(mc.scope.get()).unwrap_ptr();
    return TypeKind::new(scope) is kind;
  }
  
  func is_slice_get_ptr(self, mc: Call*): bool{
        if (!mc.scope.is_some() || !mc.name.eq("ptr") || !mc.args.empty()) {
            return false;
        }
        let scope = self.getType(mc.scope.get()).unwrap_ptr();
        return scope.is_slice();
   }
   func is_slice_get_len(self, mc: Call*): bool{
        if (!mc.scope.is_some() || !mc.name.eq("len") || !mc.args.empty()) {
            return false;
        }
        let scope = self.getType(mc.scope.get()).unwrap_ptr();
        return scope.is_slice();
  }
  //x.ptr()
  func is_array_get_ptr(self, mc: Call*): bool{
        if (!mc.scope.is_some() || !mc.name.eq("ptr") || !mc.args.empty()) {
            return false;
        }
        let scope = self.getType(mc.scope.get()).unwrap_ptr();
        return scope.is_array();
   }
   //x.len()
   func is_array_get_len(self, mc: Call*): bool{
        if (!mc.scope.is_some() || !mc.name.eq("len") || !mc.args.empty()) {
            return false;
        }
        let scope = self.getType(mc.scope.get()).unwrap_ptr();
        return scope.is_array();
  }
  
  func is_drop_call(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().print().eq("Drop") && mc.name.eq("drop");
  }
  func is_ptr_get(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().print().eq("ptr") && mc.name.eq("get");
  }
  func is_ptr_copy(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().print().eq("ptr") && mc.name.eq("copy");
  }
  func is_ptr_deref(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().print().eq("ptr") && mc.name.eq("deref");
  }
  func is_ptr_null(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().print().eq("ptr") && mc.name.eq("null");
  }
  func std_size(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().print().eq("std") && mc.name.eq("size");
  }
  func std_is_ptr(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().print().eq("std") && mc.name.eq("is_ptr");
  }
  func is_std_no_drop(mc: Call*): bool{
    return mc.is_static && mc.scope.is_some() && mc.scope.get().print().eq("std") && mc.name.eq("no_drop");
  }
  func is_print(mc: Call*): bool{
    return mc.name.eq("print") && mc.scope.is_none();
  }
  func is_printf(mc: Call*): bool{
    return mc.name.eq("printf") && mc.scope.is_none();
  }
  func is_format(mc: Call*): bool{
    return mc.name.eq("format") && mc.scope.is_none();
  }
  func is_panic(mc: Call*): bool{
    return mc.name.eq("panic") && mc.scope.is_none();
  } 
  func is_assert(mc: Call*): bool{
    return mc.name.eq("assert") && mc.scope.is_none();
  }
  func is_exit(mc: Call*): bool{
    return mc.name.eq("exit") && mc.scope.is_none();
  }

  func validate_printf(self, node: Expr*, mc: Call*){
    //check fmt literal
    let fmt: Expr* = mc.args.get_ptr(0);
    if (is_str_lit(fmt).is_none()) {
        self.err(node, "format string is not a string literal");
    }
    //check rest
    for (let i = 1; i < mc.args.len(); ++i) {
        let arg = self.getType(mc.args.get_ptr(i));
        if (!(arg.is_prim() || arg.is_pointer())) {
            self.err(node, "format arg is invalid");
        }
    }
  }

  func visit_call(self, node: Expr*, call: Call*): RType{
    if(is_drop_call(call)){
      let argt = self.visit(call.args.get_ptr(0));
      if(argt.type.is_pointer() || argt.type.is_prim()){
        return RType::new("void");
      }
      //let decl = self.get_decl(&argt);
      let helper = DropHelper{self};
      //if (!DropHelper::has_drop_impl(decl, self)) {
        if(!helper.is_drop_type(&argt)){
          return RType::new("void");
        }
      //}
    }
    if(is_printf(call)){
      self.validate_printf(node, call);
      return RType::new("void");
    }
    if(is_print(call) || is_panic(call)){
      generate_format(node, call, self);
      return RType::new("void");
    }
    if(Resolver::is_assert(call)){
      generate_assert(node, call, self);
      return RType::new("void");
    }
    if(is_format(call)){
      generate_format(node, call, self);
      return RType::new("String");
    }
    if(std_size(call)){
      if(!call.args.empty()){
        self.visit(call.args.get_ptr(0));
      }else{
        self.visit_type(call.type_args.get_ptr(0));
      }
      return RType::new("i64");
    }
    if(std_is_ptr(call)){
      self.visit_type(call.type_args.get_ptr(0));
      return RType::new("bool");
    }
    if(is_ptr_null(call)){
      if(call.type_args.len() != 1){
        self.err(node, "ptr::null() expects one type arg");
      }
      let rt = self.visit_type(call.type_args.get_ptr(0));
      rt.type = rt.type.toPtr();
      return rt;
    }
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
          return self.visit_type(&arg);
      } else {
          self.err(node, "ptr access index is not integer");
      }
    }
    if(is_ptr_copy(call)){
      if (call.args.len() != 3) {
        self.err(node, "ptr::copy() must have 3 args");
      }
      //ptr::copy(src_ptr, src_idx, elem)
      let ptr_type = self.getType(call.args.get_ptr(0));
      let idx_type = self.getType(call.args.get_ptr(1));
      let elem_type = self.getType(call.args.get_ptr(2));
      if (!ptr_type.is_pointer()) {
          self.err(node, "ptr arg is not ptr ");
      }
      if (!idx_type.eq("i32") && !idx_type.eq("i64") && !idx_type.eq("u32") && !idx_type.eq("u64") && !idx_type.eq("i8") && !idx_type.eq("i16")) {
        self.err(node, "ptr access index is not integer");
      }
      let ptr_str = ptr_type.unwrap_ptr().print();
      if (!elem_type.print().eq(&ptr_str)) {
        self.err(node, "ptr elem type dont match val type");
      }
      return RType::new("void");
    }
    if(is_ptr_deref(call)){
        //unsafe deref
        let rt = self.getType(call.args.get_ptr(0));
        if (!rt.is_pointer()) {
            self.err(node, "ptr arg is not ptr ");
        }
        return self.visit_type(rt.unwrap_ptr());
    }
    if(is_std_no_drop(call)){
      let rt = self.visit(call.args.get_ptr(0));
      return RType::new("void");
    }
    if (self.is_slice_get_ptr(call)) {
        let elem = self.getType(call.scope.get()).elem();
        return RType::new(elem.clone().toPtr());
    }
    if (self.is_slice_get_len(call)) {
        self.visit(call.scope.get());
        let type = as_type(SLICE_LEN_BITS());
        return RType::new(type);
    }
    if(self.is_array_get_len(call)){
      self.visit(call.scope.get());
      return RType::new("i64");
    }
    if(self.is_array_get_ptr(call)){
      let arr_type = self.getType(call.scope.get()).unwrap_ptr();
      return RType::new(arr_type.elem().clone().toPtr());
    }
    if(call.scope.is_none() && call.name.eq("malloc")){
      let argt = self.getType(call.args.get_ptr(0));
      if(!argt.is_prim()){
        self.err(node, "malloc arg is not integer");
      }
      if(call.type_args.empty()){
        return RType::new(Type::new("i8").toPtr());
      }else{
        let arg = self.visit_type(call.type_args.get_ptr(0));
        return RType::new(arg.type.clone().toPtr());
      }
    }
    if(node.print().eq("(0).debug(&f_678)")){
      let a = 10;
    }
    let sig = Signature::new(call, self);
    let mr = MethodResolver::new(self);
    return mr.handle(node, &sig);
  }
  
  func visit_arr_access(self, node: Expr*, aa: ArrAccess*): RType{
    let arr = self.getType(aa.arr.get());
    let idx = self.getType(aa.idx.get());
    //todo unsigned
    if (idx.print().eq("bool") || !idx.is_prim()){
      self.err(node, "array index is not an integer");
    }
    if (aa.idx2.is_some()) {
        let idx2 = self.getType(aa.idx2.get());
        if (idx2.print().eq("bool") || !idx2.is_prim()){
          self.err(node, "range end is not an integer");
        }
        let inner = arr.unwrap_ptr();
        if (inner.is_slice()) {
            return RType::new(inner.clone());
        } else if (inner.is_array()) {
            return RType::new(Type::Slice{.Node::new(-1, node.line), Box::new(inner.elem().clone())});
        } else if (arr.is_pointer()) {
            //from raw pointer
            return RType::new(Type::Slice{.Node::new(-1, node.line), Box::new(inner.clone())});
        } else {
            self.err(node, "cant make slice out of ");
        }
    }
    if (arr.is_pointer()) {
        arr = self.getType(arr.elem());
    }
    if (arr.is_array() || arr.is_slice()) {
        return self.visit_type(arr.elem());
    }
    self.err(node, "cant index: ");
    panic("");
  }
  
  func visit_array(self, node: Expr*, list: List<Expr>*, size: Option<i32>*): RType{
    if (size.is_some()) {
        let e = self.visit(list.get_ptr(0));
        let elemType = e.type.clone();
        return RType::new(Type::Array{.Node::new(-1, node.line), Box::new(elemType), *size.get()});
    }
    let elemType = self.getType(list.get_ptr(0));
    for (let i = 1; i < list.len(); ++i) {
        let elem = list.get_ptr(i);
        let cur = self.visit(elem);
        let cmp = MethodResolver::is_compatible(&cur.type, &cur.value, &elemType);
        if (cmp.is_some()) {
            let msg = format("{}\narray element type mismatch, expecting: {} got: {}({})", cmp.get(), elemType, &cur.type, elem);
            self.err(node, msg.str());
        }
    }
    return RType::new(Type::Array{.Node::new(-1, node.line), Box::new(elemType), list.len() as i32});
  }
  
  func visit_as(self, node: Expr*, lhs: Expr*, type: Type*): RType{
    let left = self.visit(lhs);
    let right = self.visit_type(type);
    //prim->prim
    if (left.type.is_prim()) {
      if(right.type.is_prim()){
        return right;
      }
      self.err(node, "invalid as expr");
    }
    if (left.type.is_pointer() && right.type.print().eq("u64")) {
      return RType::new("u64");
    }
    if (!right.type.is_pointer()) {
      self.err(node, "invalid as expr");
    }
    //derived->base
    let decl1_opt = self.get_decl(&left);
    if (decl1_opt.is_some()) {
      let decl1 = decl1_opt.unwrap();
      if(decl1.base.is_some()){
        let base_ptr = format("{}*", decl1.base.get());
        if (base_ptr.eq(right.type.print().str())) return right;
      }
    }
    return right;
  }

  func visit_is(self, node: Expr*, lhs: Expr*, rhs: Expr*): RType{
    let rt = self.visit(lhs);
    let decl1_opt = self.get_decl(&rt);
    if (decl1_opt.is_none() || !(*decl1_opt.get() is Decl::Enum)) {
        self.err(node, format("lhs of is expr is not enum: {}", rt.type));
    }
    let decl1 = decl1_opt.unwrap();
    let rt2 = self.visit(rhs);
    let decl2 = self.get_decl(&rt2).unwrap();
    if (!decl1.type.print().eq(decl2.type.print().str())) {
        self.err(node, format("rhs is not same type with lhs {} vs {}", decl1.type, decl2.type));
    }
    if let Expr::Type(ty*) = (rhs){
        findVariant(decl1, ty.name());
    }
    return RType::new("bool");
  }

  func visit_lit(self, lit: Literal*): RType{
    let kind = &lit.kind;
    let value = lit.trim_suffix().str();
    if(lit.suffix.is_some()){
      if(i64::parse(value.str()) > max_for(lit.suffix.get())){
        self.err(format("literal out of range expected: {} got: {}", lit.suffix.get(), value));
      }
      return self.visit_type(lit.suffix.get());
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
      //res.value = Option::new(value);
      assert(value.len() == 1);
      res.value = Option::new(i64::print(value.get(0)));
      value.drop();
      return res;
    }
    panic("lit");
  }

  func visit_name(self, node: Expr*, name: String*): RType{
    for(let i = self.scopes.len() - 1;i >= 0;--i){
      let scope = self.scopes.get_ptr(i);
      let vh_opt = scope.find(name);
      if(vh_opt.is_some()){
        let vh = vh_opt.unwrap();
        let res = self.visit_type(&vh.type);
        res.vh = Option::new(vh.clone());
        return res;
      }
    }
    //external globals
    let imports = self.get_imports();
    for (let i = 0;i < imports.len();++i) {
      let is = imports.get_ptr(i);
      let res = self.ctx.get_resolver(is);
      for (let j = 0;j < res.unit.globals.len();++j) {
        let glob = res.unit.globals.get_ptr(j);
        if (glob.name.eq(name)) {
          //clone to have unique id
          let expr2 = AstCopier::clone(&glob.expr, &self.unit);
          let rt = self.visit(&expr2);
          for(let gi=0;gi < self.glob_map.len();++gi){
            let old = self.glob_map.get_ptr(gi);
            if(old.name.eq(name)){
              //already have
              return rt;
            }
          }
          self.glob_map.add(GlobalInfo{glob.name.clone(), rt.clone(), res.unit.path.clone()});
          return rt;
        }
      }
    }
    self.dump();
    self.err(node, "unknown identifier");
    panic("");
  }

  func visit_cached(self, node: Expr*): RType{
    let id = node.id;
    if(id == -1) panic("id=-1");
    if(self.cache.contains(&node.id)){
      return self.cache.get_ptr(&node.id).unwrap().clone();
    }
    self.err(node, format("not cached id={} line: {}", id, node.line));
    panic("");
  }

  func visit(self, node: Expr*): RType{
    let id = node.id;
    if(id == -1) panic("id=-1");
    if(self.cache.contains(&node.id)){
      return self.cache.get_ptr(&node.id).unwrap().clone();
    }
    let res = self.visit_nc(node);
    self.cache.add(node.id, res.clone());
    //print("cached id={} line: {} {}\n", id, node.line, node);
    return res.clone();
  }
  
  func visit_nc(self, node: Expr*): RType{
    if let Expr::Lit(lit*)=(node){
      return self.visit_lit(lit);
    }else if let Expr::Type(type*) = (node){
      let res = self.visit_type(node, type);
      //if(res.is_decl()){
        /*let decl = self.get_decl(&res).unwrap();
        if(decl.base.is_some()){
          self.err(node, "base is not initialized");
        }*/
      //}
      return res;
    }else if let Expr::Infix(op*, lhs*, rhs*) = (node){
      return self.visit_infix(node, op, lhs.get(), rhs.get());
    }else if let Expr::Call(call*) = (node){
      let res = self.visit_call(node, call);
      return res;
    }else if let Expr::Name(name*) = (node){
      return self.visit_name(node, name);
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
    panic("visit expr '{}'", node);
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
  panic("infix_result: {}, {}", l, r);
}

//statements-------------------------------------
impl Resolver{
  func visit(self, node: Stmt*){
    if(verbose_stmt()){
      print("visit stmt {}\n", node);
    }
    if let Stmt::Expr(e*) = (node){
      self.visit(e);
      return;
    }else if let Stmt::Block(b*) = (node){
      self.visit(b);
      return;
    }else if let Stmt::Ret(e*) = (node){
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
    }else if let Stmt::For(f*) = (node){
      self.newScope();
      if(f.var_decl.is_some()){
        self.visit(f.var_decl.get());
      }
      if(f.cond.is_some()){
        if (!self.isCondition(f.cond.get())) {
            self.err(f.cond.get(), "for statement expr is not a bool");
        }
      }
      for (let i = 0;i < f.updaters.len();++i) {
        self.visit(f.updaters.get_ptr(i));
      }
      self.inLoop+=1;
      self.visit(f.body.get());
      self.inLoop-=1;
      self.dropScope();
      return;
    }else if let Stmt::If(is*) = (node){
      self.visit_if(node, is);
      return;
    }else if let Stmt::IfLet(is*) = (node){
      self.visit_iflet(node, is);
      return;
    }else if let Stmt::While(e*, b*) = (node){
      self.visit_while(node, e, b.get());
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
    panic("visit stmt {}", node);
  }
  
  func visit_while(self, node: Stmt*, cond: Expr*, body: Stmt*){
    if (!self.isCondition(cond)) {
        self.err(node, "while statement expr is not a bool");
    }
    ++self.inLoop;
    self.newScope();
    self.visit(body);
    --self.inLoop;
    self.dropScope();
  }
  
  func visit_if(self, node: Stmt*, is: IfStmt*){
    if (!self.isCondition(&is.cond)) {
        self.err(&is.cond, "if condition is not a boolean");
    }
    self.newScope();
    self.visit(is.then.get());
    self.dropScope();
    if (is.else_stmt.is_some()) {
        self.newScope();
        self.visit(is.else_stmt.get());
        self.dropScope();
    }
  }

  func visit_iflet(self, node: Stmt*, is: IfLet*){
    //check lhs
    let rt = self.visit_type(&is.type);
    let decl_opt = self.get_decl(&rt);
    if (decl_opt.is_none() || !decl_opt.unwrap().is_enum()) {
        let msg = format("if let type is not enum: {}", is.type);
        self.err(node, msg);
    }
    //check rhs
    let rhs = self.visit(&is.rhs);
    let rhs_opt = self.get_decl(&rhs);
    if (rhs_opt.is_none() || !rhs_opt.unwrap().is_enum()) {
      let msg = format("if let rhs is not enum: {}", rhs.type);
      self.err(node, msg);
    }
    //match variant
    let decl: Decl* = decl_opt.unwrap();
    let index = Resolver::findVariant(decl, is.type.name());
    let variant = decl.get_variants().get_ptr(index);
    if (variant.fields.len() != is.args.len()) {
        let msg = format("if let args size mismatch got:{} expected: {}", is.args.len(), variant.fields.len());
        self.err(node, msg);
    }
    //init arg variables
    self.newScope();
    for (let i = 0;i < is.args.len();++i) {
        let arg = is.args.get_ptr(i);
        let field = variant.fields.get_ptr(i);
        let ty = field.type.clone();
        if (arg.is_ptr) {
            ty = ty.toPtr();
        } 
        self.addScope(arg.name.clone(), ty.clone(), false, arg.id);
        self.cache.add(arg.id, RType::new(ty));
    }
    self.visit(is.then.get());
    self.dropScope();
    if (is.else_stmt.is_some()) {
        self.newScope();
        self.visit(is.else_stmt.get());
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
      self.addScope(f.name.clone(), res.type.clone(), false, f.id);
    }
  }

  func visit(self, node: Fragment*): RType{
    let rhs = self.visit(&node.rhs);
    if(rhs.type.is_void()){
      self.err(node.line, format("void variable, {}", node.name));
    }
    if(node.type.is_none()){
      return rhs.clone();
    }
    let res = self.visit_type(node.type.get());
    let err_opt = MethodResolver::is_compatible(&rhs.type, &rhs.value, &res.type);
    if(err_opt.is_some()){
      self.err(node.line, format("type mismatch {} vs {}\n{}", res.type, rhs.type, err_opt.get()));
    }
    err_opt.drop();
    rhs.drop();
    return res;
  }
}