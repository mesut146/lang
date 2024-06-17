import parser/resolver
import parser/ast
import parser/printer
import parser/utils
import parser/copier
import parser/bridge
import parser/compiler_helper
import parser/alloc_helper
import parser/debug_helper
import parser/stmt_emitter
import parser/expr_emitter
import parser/ownership
import parser/cache
import std/map
import std/io
import std/libc
import std/stack

struct Compiler{
  ctx: Context;
  resolver: Option<Resolver*>;
  main_file: Option<String>;
  llvm: llvm_holder;
  compiled: List<String>;
  protos: Option<Protos>;
  NamedValues: Map<String, Value*>;
  globals: Map<String, Value*>;
  allocMap: Map<i32, Value*>;
  curMethod: Option<Method*>;
  loops: List<BasicBlock*>;
  loopNext: List<BasicBlock*>;
  own: Option<Own>;
}
impl Drop for Compiler{
  func drop(*self){
    Drop::drop(self.ctx);
    Drop::drop(self.main_file);
    Drop::drop(self.llvm);
    Drop::drop(self.compiled);
    Drop::drop(self.protos);
    Drop::drop(self.NamedValues);
    Drop::drop(self.globals);
    Drop::drop(self.allocMap);
    Drop::drop(self.loops);
    Drop::drop(self.loopNext);
    Drop::drop(self.own);
  }
}

struct llvm_holder{
  target_machine: TargetMachine*;
  target_triple: CStr;
  di: Option<DebugInfo>;
}
impl Drop for llvm_holder{
  func drop(*self){
    Drop::drop(self.target_triple);
    Drop::drop(self.di);
    destroy_ctx();
  }
}

struct Protos{
  classMap: Map<String, llvm_Type*>;
  funcMap: Map<String, Function*>;
  libc: Map<str, Function*>;
  stdout_ptr: Value*;
  std: Map<str, StructType*>;
  cur: Option<Function*>;
}

impl Protos{
  func new(): Protos{
    let res = Protos{
      classMap: Map<String, llvm_Type*>::new(),
      funcMap: Map<String, Function*>::new(),
      libc: Map<str, Function*>::new(),
      stdout_ptr: make_stdout(),
      std: Map<str, StructType*>::new(),
      cur: Option<Function*>::new()};
      res.init();
      return res;
  }
  func init(self){
      let sliceType = make_slice_type();
      self.std.add("slice", sliceType);
      self.std.add("str", make_string_type(sliceType as llvm_Type*));
      self.libc.add("printf", make_printf());
      self.libc.add("fflush", make_fflush());
      self.libc.add("malloc", make_malloc());
  }
  func get(self, d: Decl*): llvm_Type*{
    let name = d.type.print();
    return self.get(&name);
  }
  func get(self, name: String*): llvm_Type*{
    let res = self.classMap.get_ptr(name);
    return *res.unwrap();
  }
  func dump(self){
    print("dump classmap\n");
    for(let i=0;i<self.classMap.len();++i){
      let e = self.classMap.get_pair_idx(i).unwrap();
      print("{}\n", e.a);
    }
  }
  func libc(self, nm: str): Function*{
    return *self.libc.get_ptr(&nm).unwrap();
  }
  func std(self, nm: str): StructType*{
    return *self.std.get_ptr(&nm).unwrap();
  }
  func get_func(self, mangled: String*): Function*{
    let opt = self.funcMap.get_ptr(mangled);
    if(opt.is_none()){
      panic("no proto for {}, {}", mangled, demangle(mangled.str()));
    }
    return *opt.unwrap();
  }
  func get_func(self, m: Method*): Function*{
    let id = mangle(m);
    let res = self.get_func(&id);
    id.drop();
    return res;
  }
}

func has_main(unit: Unit*): bool{
  for (let i=0;i<unit.items.len();++i) {
    let it = unit.items.get_ptr(i);
    if let Item::Method(m*) = (it){
      if(is_main(m)){
        return true;
      }
    }
  }
  return false;
}

func get_out_file(path: str, c: Compiler*): String{
  let name = getName(path);
  let res = format("{}/{}-bt.o", c.ctx.out_dir, trimExtenstion(name));
  return res;
}

func trimExtenstion(name: str): str{
  let i = name.lastIndexOf(".");
  if(i == -1){
    return name;
  }
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
    let name_c = name.str().cstr();
    make_module(name_c.ptr(), self.target_machine, self.target_triple.ptr());
    name_c.drop();
    make_builder();
    self.di = Option::new(DebugInfo::new(path, true));
  }

  func new(): llvm_holder{
    InitializeAllTargetInfos();
    InitializeAllTargets();
    InitializeAllTargetMCs();
    InitializeAllAsmParsers();
    InitializeAllAsmPrinters();
    
    let target_triple = getDefaultTargetTriple2();
    let target_machine = createTargetMachine(target_triple.ptr());
    return llvm_holder{target_triple: target_triple, target_machine: target_machine, di: Option<DebugInfo>::new()};

    //todo cache
  }

}

impl Compiler{
  func new(ctx: Context): Compiler{
    let vm = llvm_holder::new();
    return Compiler{ctx: ctx,
     resolver: Option<Resolver*>::None,
     main_file: Option<String>::new(),
     llvm: vm,
     compiled: List<String>::new(),
     protos: Option<Protos>::new(),
     NamedValues: Map<String, Value*>::new(),
     globals: Map<String, Value*>::new(),
     allocMap: Map<i32, Value*>::new(),
     curMethod: Option<Method*>::new(),
     loops: List<BasicBlock*>::new(),
     loopNext: List<BasicBlock*>::new(),
     own: Option<Own>::new()
    };
  }

  func get_resolver(self): Resolver*{
    return *self.resolver.get();
  }

  func unit(self): Unit*{
    return &self.get_resolver().unit;
  }

  func compile(self, path: str, cache: Cache*): String{
    let outFile: String = get_out_file(path, self);
    if(!cache.need_compile(path, outFile.str())){
      self.compiled.add(outFile.clone());
      return outFile;
    }
    let ext = Path::ext(path);
    if (!ext.eq("x")) {
      panic("invalid extension {}", ext);
    }
    if(self.ctx.verbose){
      print("compiling {}\n", path);
    }
    let resolv = self.ctx.create_resolver(path);
    self.resolver = Option::new(resolv);//Resolver*
    if (has_main(self.unit())) {
      self.main_file = Option::new(path.str());
      if (!self.ctx.single_mode) {//compile last
          print("skip main file\n");
          return outFile;
      }
    }
    self.get_resolver().resolve_all();
    self.llvm.initModule(path);
    self.createProtos();
    self.init_globals();
    
    let methods = getMethods(self.unit());
    for (let i = 0;i < methods.len();++i) {
      let m = *methods.get_ptr(i);
      self.genCode(m);
    }
    //generic methods from resolver
    for (let i = 0;i < self.get_resolver().generated_methods.len();++i) {
        let m = self.get_resolver().generated_methods.get_ptr(i).get();
        self.genCode(m);
    }
    methods.drop();
    
    let name = getName(path);
    let llvm_file = format("{}/{}-bt.ll", &self.ctx.out_dir, trimExtenstion(name));
    let llvm_file_cstr = llvm_file.cstr();
    emit_llvm(llvm_file_cstr.ptr());
    if(self.ctx.verbose){
      print("writing {}\n", llvm_file_cstr);
    }
    llvm_file_cstr.drop();
    self.compiled.add(outFile.clone());
    let outFile_cstr = CStr::new(outFile.clone());
    emit_object(outFile_cstr.ptr(), self.llvm.target_machine, self.llvm.target_triple.ptr());
    if(self.ctx.verbose){
      print("writing {}\n", outFile_cstr);
    }
    Drop::drop(outFile_cstr);
    self.cleanup();
    cache.update(path);
    cache.write_cache();
    return outFile;
  }

  func cleanup(self){
    self.NamedValues.clear();
  }

  func init_globals(self){
    let resolv = self.get_resolver();
    //extern globals
    /*let imports = self.get_resolver().get_imports();
    for(let i = 0;i < imports.len();++i){
      let is = imports.get_ptr(i);
      let resolver = self.get_resolver().ctx.get_resolver(is);
      for(let j = 0;j < resolver.unit.globals.len();++j){
        let gl = resolver.unit.globals.get_ptr(j);
        let rt = self.get_resolver().glob_map.get_ptr(&gl.id).unwrap();
        let ty = self.mapType(&rt.type);
        let init = ptr::null<Constant>();
        let glob = make_global(gl.name.clone().cstr().ptr(), ty, init);
        self.globals.add(gl.name.clone(), glob as Value*);
      }
    }*/
    for(let i = 0;i < resolv.glob_map.len();++i){
      let pair = resolv.glob_map.get_pair_idx(i).unwrap();
      let ty = self.mapType(&pair.b.type);
      let init = ptr::null<Constant>();
      let glob = make_global(pair.a.clone().cstr().ptr(), ty, init);
      self.globals.add(pair.a.clone(), glob as Value*);
    }
    if(self.get_resolver().unit.globals.empty()){
      return;
    }
    for(let j = 0;j < self.get_resolver().unit.globals.len();++j){
      let gl = self.get_resolver().unit.globals.get_ptr(j);
      let rt = self.get_resolver().visit(&gl.expr);
      let ty = self.mapType(&rt.type);
      let init = ptr::null<Constant>();
      if(rt.type.is_prim()){
        let rhs_str = gl.expr.print();
        init = makeInt(i64::parse(rhs_str.str()), self.getSize(&rt.type) as i32) as Constant*;
      }else{
        panic("glob struct");
      }
      let glob = make_global(gl.name.clone().cstr().ptr(), ty, init);
      self.globals.add(gl.name.clone(), glob as Value*);
    }
  }

  //make all struct decl & method decl used by this module
  func createProtos(self){
    self.protos = Option::new(Protos::new());
    let p = self.protos.get();
    self.make_decl_protos();
    //methods
    let methods: List<Method*> = getMethods(self.unit());
    //print("local m\n");
    for (let i = 0;i < methods.len();++i) {
      let m = methods.get(i);
      self.make_proto(m);
    }
    methods.drop();
    //generic methods from resolver
    //print("gen m\n");
    for (let i = 0;i < self.get_resolver().generated_methods.len();++i) {
        let m = self.get_resolver().generated_methods.get_ptr(i).get();
        self.make_proto(m);
    }
    //print("used m\n");
    for (let i = 0;i < self.get_resolver().used_methods.len();++i) {
        let m = self.get_resolver().used_methods.get(i);
        self.make_proto(m);
    }
  }

  func genCode(self, m: Method*){
    //print("gen {}\n", m.name);
    if(m.body.is_none()) return;
    if(m.is_generic) return;
    self.curMethod = Option<Method*>::new(m);
    self.own = Option::new(Own::new(self, m));
    let mangled = mangle(m);
    let f = self.protos.get().get_func(&mangled);
    self.protos.get().cur = Option::new(f);
    let bb = create_bb2(f);
    self.NamedValues.clear();
    SetInsertPoint(bb);
    self.llvm.di.get().dbg_func(m, f, self);
    self.makeLocals(m.body.get());
    self.allocParams(m);
    self.storeParams(m,f);
    //todo call globals

    self.visit_block(m.body.get());
    let exit = Exit::get_exit_type(m.body.get());
    if(!exit.is_exit() && m.type.is_void()){
      self.own.get().do_return();
      if(is_main(m)){
        CreateRet(makeInt(0, 32));
      }else{
        CreateRetVoid();
      }
    }
    exit.drop();
    self.llvm.di.get().finalize();
    verifyFunction(f);
    mangled.drop();
    Drop::drop(self.own);
    self.own = Option<Own>::new();
  }
  
  func makeLocals(self, b: Block*){
    //allocMap.clear();
    let ah = AllocHelper::new(self);
    ah.visit(b);
  }
  
  func allocParams(self, m: Method*){
    let p = self.protos.get();
    let ff = p.get_func(m);
    if (m.self.is_some()) {
        let prm = m.self.get();
        self.alloc_prm(prm);
    }
    for (let i=0;i<m.params.len();++i) {
        let prm = m.params.get_ptr(i);
        self.alloc_prm(prm);
    }
  }

  func alloc_prm(self, prm: Param*){
    let ty = self.mapType(&prm.type);
    let ptr = CreateAlloca(ty);
    let name_c = prm.name.clone().cstr();
    Value_setName(ptr, name_c.ptr());
    name_c.drop();
    self.NamedValues.add(prm.name.clone(), ptr);
  }

  func copy(self, trg: Value*, src: Value*, type: Type*){
    let size = self.getSize(type) / 8;
    CreateMemCpy(trg, src, size);
  }

  func store_prm(self, prm: Param*, f: Function*, argIdx: i32){
    let ptr = *self.NamedValues.get_ptr(&prm.name).unwrap();
    let val = get_arg(f, argIdx) as Value*;
    if(is_struct(&prm.type)){
      self.copy(ptr, val, &prm.type);
      self.own.get().add_prm(prm, ptr);
    }else{
      CreateStore(val, ptr);
    }
  }

  func storeParams(self, m: Method*, f: Function*){
    let argIdx = 0;
    if(is_struct(&m.type)){
      ++argIdx;//sret
    }
    let argNo = 1;
    if (m.self.is_some()) {
      let prm = m.self.get();
      self.store_prm(prm, f, argIdx);
      self.llvm.di.get().dbg_prm(prm, argNo, self);
      ++argIdx;
      ++argNo;
    }
    for(let i = 0;i < m.params.len();++i){
      let prm = m.params.get_ptr(i);
      self.store_prm(prm, f, argIdx);
      self.llvm.di.get().dbg_prm(prm, argNo, self);
      ++argIdx;
      ++argNo;
    }
  }
  
  func get_alloc(self, e: Expr*): Value*{
    let ptr = self.allocMap.get_ptr(&e.id);
    if(ptr.is_none()){
      self.get_resolver().err(e, "get_alloc() not set");
    }
    return *ptr.unwrap();
  }
  func get_alloc(self, id: i32): Value*{
    let ptr = self.allocMap.get_ptr(&id);
    return *ptr.unwrap();
  }
  
  func gep2(self, ptr: Value*, idx: i32, ty: llvm_Type*): Value*{
    return CreateStructGEP(ptr, idx, ty);
  }

  func cur_func(self): Function*{
    return self.protos.get().cur.unwrap();
  }

  func add_bb(self, bb: BasicBlock*){
    func_insert(self.cur_func(), bb);
  }

  func set_and_insert(self, bb: BasicBlock*){
    func_insert(self.cur_func(), bb);
    SetInsertPoint(bb);
  }

  func getType(self, e: Expr*): Type{
    let rt = self.get_resolver().visit_cached(e);
    return rt.type.clone();
  }

  func build_library(compiled: List<String>*, name: str, out_dir: str, is_shared: bool): String{
    create_dir(out_dir);
    let cmd = "".str();
    if(is_shared){
      cmd.append("clang-16 -shared -o ");
    }else{
      cmd.append("ar rcs ");
    }
    let path = format("{}/{}", out_dir, name);
    cmd.append(&path);
    cmd.append(" ");
    for(let i = 0;i < compiled.len();++i){
      let file = compiled.get_ptr(i);
      cmd.append(file.str());
      cmd.append(" ");
    }

    let cmd_s = cmd.cstr();
    if(system(cmd_s.ptr()) == 0){
      print("build library {}\n", path);
    }else{
      panic("link failed '{}'", cmd_s.get());
    }
    cmd_s.drop();
    return path;
  }

  func link(compiled: List<String>*, out_dir: str, name: str, args: str): String{
    if(exist(name)){
      let name_c: CStr = name.cstr();
      remove(name_c.ptr());
      name_c.drop();
    }
    let path = format("{}/{}", out_dir, name);
    create_dir(out_dir);
    let cmd = "clang-16 ".str();
    cmd.append("-o ");
    cmd.append(&path);
    cmd.append(" ");
    for(let i = 0;i < compiled.len();++i){
      let obj_file = compiled.get_ptr(i);
      cmd.append(obj_file.str());
      cmd.append(" ");
    }
    cmd.append(args);
    let cmd_s = cmd.cstr();
    if(system(cmd_s.ptr()) == 0){
      //run if linked
      print("build binary {}\n", path);
    }else{
      panic("link failed '{}'", cmd_s);
    }
    cmd_s.drop();
    return path;
  }

  func run(path: String){
    let path_c: CStr = path.cstr();
    let code = system(path_c.ptr());
    if(code != 0){
      panic("error while running {} code={}", path_c, code);
    }
    path_c.drop();
  }

  func compile_single(src_dir: str, out_dir: str, file: str, args: str){
    create_dir(out_dir);
    let ctx = Context::new(src_dir.str(), out_dir.str());
    let cmp = Compiler::new(ctx);
    let compiled = List<String>::new();
    use_cache = false;
    let cache = Cache::new(out_dir);
    let obj = cmp.compile(file, &cache);
    compiled.add(obj);
    let path = link(&compiled, out_dir, bin_name(file).str(), args);
    run(path);
    Drop::drop(cmp);
  }

  func compile_dir(src_dir: str, out_dir: str, root: str, lt: LinkType): String{
    create_dir(out_dir);
    let cache = Cache::new(out_dir);
    cache.read_cache();
    let list: List<String> = list(src_dir);
    let compiled = List<String>::new();
    for(let i = 0;i < list.len();++i){
      let name = list.get_ptr(i).str();
      if(!name.ends_with(".x")) continue;
      let file: String = format("{}/{}", src_dir, name);
      if(is_dir(file.str())) continue;
      let ctx = Context::new(root.str(), out_dir.str());
      let cmp = Compiler::new(ctx);
      let obj = cmp.compile(file.str(), &cache);
      Drop::drop(cmp);
      compiled.add(obj);
      file.drop();
    }
    list.drop();
    if let LinkType::Binary(bin_name, args, run) = (&lt){
      let path = link(&compiled, out_dir, bin_name, args);
      compiled.drop();
      if(run){
        Compiler::run(path);
      }
      return path;
    }
    else if let LinkType::Static(lib_name) = (&lt){
      let res = Compiler::build_library(&compiled, lib_name, out_dir, false);
      compiled.drop();
      return res;
    }else{
      panic("compile_dir");
    }
  }
 
}//Compiler

enum LinkType{
  Binary(name: str, args: str, run: bool),
  Static(name: str),
  Dynamic
}