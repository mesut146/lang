import parser/resolver
import parser/ast
import parser/printer
import parser/utils
import parser/copier
import parser/bridge
import parser/compiler_helper
import parser/alloc_helper
import std/map
import std/io

struct Compiler{
  ctx: Context;
  config: Config;
  resolver: Resolver*;
  main_file: Option<String>;
  llvm: llvm_holder;
  compiled: List<String>;
  protos: Option<Protos>;
  NamedValues: Map<String, Value*>;
}

struct Protos{
  classMap: Map<String, llvm_Type*>;
  funcMap: Map<String, Function*>;
  libc: Map<str, Function*>;
  stdout_ptr: Value*;
  std: Map<str, StructType*>;
}

impl Protos{
  func new(): Protos{
    let res = Protos{
      classMap: Map<String, llvm_Type*>::new(),
      funcMap: Map<String, Function*>::new(),
      libc: Map<str, Function*>::new(),
      stdout_ptr: make_stdout(),
      std: Map<str, StructType*>::new()};
      res.init();
      return res;
  }
  func init(self){
      let sliceType = make_slice_type();
      self.std.add("slice", sliceType);
      self.std.add("str", make_string_type(sliceType as llvm_Type*));
      self.libc.add("printf", make_printf());
      self.libc.add("exit", make_exit());
      self.libc.add("fflush", make_fflush());
      self.libc.add("malloc", make_malloc());
  }
  func get(self, d: Decl*): llvm_Type*{
    let name = d.type.print();
    return self.get(&name);
  }
  func get(self, name: String*): llvm_Type*{
    let res = self.classMap.get_p(name);
    return res.unwrap();
  }
  func dump(self){
    for(let i=0;i<self.classMap.len();++i){
      let e = self.classMap.get_idx(i).unwrap();
      print("%s\n", e.a.cstr());
    }
  }
  func libc(self, nm: str): Function*{
    return self.libc.get_p(&nm).unwrap();
  }
  func std(self, nm: str): StructType*{
    return self.std.get_p(&nm).unwrap();
  }
  func get_func(self, nm: String*): Function*{
    return self.funcMap.get_p(nm).unwrap();
  }
  func get_func(self, m: Method*): Function*{
    let id = mangle(m);
    return self.funcMap.get_p(&id).unwrap();
  }
}

struct llvm_holder{
  target_machine: TargetMachine*;
  target_triple: String;
}

struct Config{
  verbose: bool;
  single_mode: bool;
}

func dummy_resolver(ctx: Context*): Resolver*{
  let path = "../tests/src/std/str.x".str();
  return ctx.create_resolver(&path);
}

func is_main(m: Method*): bool{
  return m.name.eq("main") && m.params.empty();
}

func has_main(unit: Unit*): bool{
  for (let i=0;i<unit.items.len();++i) {
    let it = unit.items.get_ptr(i);
    if let Item::Method(m*)=(it){
      if(is_main(m)){
        return true;
      }
    }
  }
  return false;
}

func get_out_file(path: str): String{
  let name = getName(path);
  let noext = trimExtenstion(name).str();
  noext.append(".o");
  return noext;
}

func trimExtenstion(name: str): str{
  let i = name.lastIndexOf(".");
  return name.substr(0, i);
}

func getName(path: str): str{
  let i = path.lastIndexOf("/");
  return path.substr(i + 1);
}

impl llvm_holder{
  func initModule(self, path: str){
    let name = getName(path);
    make_ctx();
    make_module(name.cstr(), self.target_machine, self.target_triple.cstr());
    make_builder();
    //c->init_dbg(path);
  }

  func new(): llvm_holder{
    InitializeAllTargetInfos();
    InitializeAllTargets();
    InitializeAllTargetMCs();
    InitializeAllAsmParsers();
    InitializeAllAsmPrinters();
    
    let target_triple = getDefaultTargetTriple2();
    let target_machine = createTargetMachine(target_triple.cstr());
    return llvm_holder{target_triple: target_triple, target_machine: target_machine};

    //todo cache
  }

}

impl Compiler{
  func new(ctx: Context): Compiler{
    let vm = llvm_holder::new();
    return Compiler{ctx: ctx, config: Config{verbose: true, single_mode: false},
     resolver: dummy_resolver(&ctx), main_file: Option<String>::new(),
     llvm: vm,
     compiled: List<String>::new(),
     protos: Option<Protos>::new(),
     NamedValues: Map<String, Value*>::new()};
  }

  func unit(self): Unit*{
    return &self.resolver.unit;
  }

  func compile(self, path0: str): String{
    //print("compile %s\n", path0.cstr());
    let path = Path::new(path0.str());
    let outFile = get_out_file(path0);
    let ext = path.ext();
    if (!ext.eq("x")) {
      panic("invalid extension %s", ext.cstr());
    }
    if(self.config.verbose){
      print("compiling %s\n", path0.cstr());
    }
    self.resolver = self.ctx.create_resolver(path0);
    if (has_main(self.unit())) {
      self.main_file = Option::new(path0.str());
      if (!self.config.single_mode) {//compile last
          return outFile;
      }
    }
    self.resolver.resolve_all();
    self.llvm.initModule(path0);
    self.createProtos();
    //init_globals(this);
    
    let methods = getMethods(self.unit());
    for (let i=0;i<methods.len();++i) {
      let m = methods.get(i);
      self.genCode(m);
    }
    //generic methods from resolver
    for (let i=0;i<self.resolver.generated_methods.len();++i) {
        let m = self.resolver.generated_methods.get_ptr(i);
        self.genCode(m);
    }
    
    let name = getName(path0);
    let llvm_file = Fmt::format("{}.lll", trimExtenstion(name));
    emit_llvm(llvm_file.cstr());
    if(self.config.verbose){
      print("writing %s\n", llvm_file.cstr());
    }
    self.compiled.add(outFile);
    return outFile;
    //panic("");
  }

  //make all struct decl & method decl used by this module
  func createProtos(self){
    self.protos = Option::new(Protos::new());
    let p = self.protos.get();
    let list = List<Decl*>::new();
    getTypes(self.unit(), &list);
    for (let i=0;i<self.resolver.used_types.len();++i) {
      let decl = self.resolver.used_types.get(i);
      if (decl.is_generic) {
          continue;
      }
      list.add(decl);
    }
    //sort(&list, self.resolver);
    //first create just protos to fill later
    for(let i=0;i<list.len();++i){
      let decl = list.get(i);
      let st = make_decl_proto(decl);
      p.classMap.add(decl.type.print(), st as llvm_Type*);
    }
    //fill with elems
    for(let i=0;i<list.len();++i){
      let decl = list.get(i);
      make_decl(p, self.resolver, decl, p.get(decl) as StructType*);
    }
    //todo di proto
    //methods
    let methods = getMethods(self.unit());
    for (let i=0;i<methods.len();++i) {
      let m = methods.get(i);
      make_proto(p, self.resolver, m);
    }
    //generic methods from resolver
    for (let i=0;i<self.resolver.generated_methods.len();++i) {
        let m = self.resolver.generated_methods.get_ptr(i);
        make_proto(p, self.resolver, m);
    }
    for (let i=0;i<self.resolver.used_methods.len();++i) {
        let m=self.resolver.used_methods.get(i);
        make_proto(p, self.resolver, m);
    }
  }

  func genCode(self, m: Method*){
    //print("gen %s\n", m.name.cstr());
    if(m.body.is_none()) return;
    if(m.is_generic) return;
    let id = mangle(m);
    let f = self.protos.get().get_func(&id);
    let bb = create_bb2(f);
    SetInsertPoint(bb);
    self.allocParams(m);
    self.makeLocals(m.body.get());
    //storeParams(curMethod, this);
  }
  
  func makeLocals(self, b: Block*){
    //allocMap.clear();
    let ah = AllocHelper::new(self);
    ah.visit(b);
  }
  
  func allocParams(self, m: Method*){
    let p = self.protos.get();
    let ff = p.get_func(m);
    let arg_idx = 0;
    //if (isRvo(m)) arg_idx+=1;
    if (m.self.is_some()) {
        let prm = m.self.get();
        let ty = mapType(p, self.resolver, &prm.type);
        let ptr = CreateAlloca(ty);
        Value_setName(ptr, prm.name.cstr());
        self.NamedValues.add(prm.name.clone(), ptr);
    }
    for (let i=0;i<m.params.len();++i) {
        let prm = m.params.get_ptr(i);
        let ty = mapType(p, self.resolver, &prm.type);
        let ptr = CreateAlloca(ty);
        Value_setName(ptr, prm.name.cstr());
        self.NamedValues.add(prm.name.clone(), ptr);
    }
  }
 
}