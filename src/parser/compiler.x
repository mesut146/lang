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
import parser/own_model
import parser/cache
import parser/derive
import parser/incremental
import std/map
import std/io
import std/libc
import std/stack
import std/any
import std/th
import std/llist

static bootstrap = false;
static inline_rvo = false;

func get_linker(): str{
  let opt = std::getenv("LD");
  if(opt.is_some()){
    return opt.unwrap();
  }
  return "clang++-19";
}

enum LinkType{
  Binary(name: String, args: String, run: bool),
  Static(name: String),
  Dynamic(name: String),
  None
}

struct CompilerConfig{
  file: String;
  src_dirs: List<String>;
  out_dir: String;
  args: String;
  lt: LinkType;
  std_path: Option<String>;
  root_dir: Option<String>;
  jobs: i32;
  verbose_all: bool;
  incremental_enabled: bool;
  use_cache: bool;
  llvm_only: bool;
}

struct LoopInfo{
  begin_bb: BasicBlock*;
  next_bb: BasicBlock*;
}

struct Compiler{
  ctx: Context;
  resolver: Option<Resolver*>;
  llvm: llvm_holder;
  protos: Option<Protos>;
  NamedValues: HashMap<String, Value*>;
  globals: HashMap<String, Value*>;
  allocMap: HashMap<i32, Value*>;
  curMethod: Option<Method*>;
  loops: List<LoopInfo>;
  own: Option<Own>;
  string_map: HashMap<String, Value*>;
  config: CompilerConfig*;
  cache: Cache*;
}
impl Compiler{
  func new(ctx: Context, config: CompilerConfig*, cache: Cache*): Compiler{
    let vm = llvm_holder::new();
    return Compiler{ctx: ctx,
     resolver: Option<Resolver*>::new(),
     llvm: vm,
     protos: Option<Protos>::new(),
     NamedValues: HashMap<String, Value*>::new(),
     globals: HashMap<String, Value*>::new(),
     allocMap: HashMap<i32, Value*>::new(),
     curMethod: Option<Method*>::new(),
     loops: List<LoopInfo>::new(),
     own: Option<Own>::new(),
     string_map: HashMap<String, Value*>::new(),
     config: config,
     cache: cache,
    };
  }
}

struct llvm_holder{
  target_machine: TargetMachine*;
  target_triple: CStr;
  di: Option<DebugInfo>;
}
impl Drop for llvm_holder{
  func drop(*self){
    self.target_triple.drop();
    self.di.drop();
    destroy_ctx();
    destroy_llvm(self.target_machine);
  }
}

struct Protos{
  classMap: HashMap<String, llvm_Type*>;
  funcMap: HashMap<String, Function*>;
  libc: HashMap<str, Function*>;
  stdout_ptr: Value*;
  std: HashMap<str, StructType*>;
  cur: Option<Function*>;
  compiler: Compiler*;
}
impl Drop for Protos{
  func drop(*self){
    /*for(let i = 0;i < self.libc.len();++i){
      let pair = self.libc.get_pair_idx(i).unwrap();
      Function_delete(pair.b);
    }*/
    self.classMap.drop();
    self.funcMap.drop();
    self.libc.drop();
    self.std.drop();
  }
}

impl Protos{
  func new(compiler: Compiler*): Protos{
    let res = Protos{
      classMap: HashMap<String, llvm_Type*>::new(),
      funcMap: HashMap<String, Function*>::new(),
      libc: HashMap<str, Function*>::new(),
      stdout_ptr: make_stdout(),
      std: HashMap<str, StructType*>::new(),
      cur: Option<Function*>::new(),
      compiler: compiler
    };
    res.init();
    return res;
  }
  func init(self){
      let sliceType = make_slice_type();
      self.std.add("slice", sliceType);
      self.libc.add("printf", make_printf());
      self.libc.add("sprintf", make_sprintf());
      self.libc.add("fflush", make_fflush());
      self.libc.add("malloc", make_malloc());
  }
  func get(self, d: Decl*): llvm_Type*{
    let name = d.type.print();
    let res = self.get(&name);
    name.drop();
    return res;
  }
  func get(self, name: String*): llvm_Type*{
    let res = self.classMap.get(name);
    return *res.unwrap();
  }
  func libc(self, nm: str): Function*{
    return *self.libc.get(&nm).unwrap();
  }
  func std(self, nm: str): StructType*{
    return *self.std.get(&nm).unwrap();
  }
  /*func get_func(self, mangled: String*): Function*{
    let opt = self.funcMap.get(mangled);
    if(opt.is_none()){
      panic("no proto for {}, {}", mangled, demangle(mangled.str()));
    }
    return *opt.unwrap();
  }*/
  func make_proto(self, m: Method*){
    if(m.is_generic) return;
    self.get_func(m);
  }
  func get_func(self, m: Method*): Function*{
    let mangled = mangle(m);
    let opt = self.funcMap.get(&mangled);
    if(opt.is_none()){
      mangled.drop();
      return self.compiler.make_proto(m).unwrap();
      //panic("no proto for {}, {}", mangled, demangle(mangled.str()));
    }
    mangled.drop();
    return *opt.unwrap();
  }
}

func has_main(unit: Unit*): bool{
  for (let i = 0;i < unit.items.len();++i) {
    let it = unit.items.get(i);
    if let Item::Method(m) = it{
      if(is_main(m)){
        return true;
      }
    }
  }
  return false;
}

func get_out_file(path: str, out_dir: str): String{
  let name = getName(path);
  let res = format("{}/{}.o", out_dir, trimExtenstion(name));
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
    self.di = Option::new(DebugInfo::new(path));
  }

  func init_llvm(){
    //InitializeAllTargetInfos();
    // InitializeAllTargets();
    // InitializeAllTargetMCs();
    // InitializeAllAsmParsers();
    // InitializeAllAsmPrinters();

    llvm_InitializeX86TargetInfo();
    llvm_InitializeX86Target();
    llvm_InitializeX86TargetMC();
    llvm_InitializeX86AsmParser();
    llvm_InitializeX86AsmPrinter();

    llvm_InitializeAArch64TargetInfo();
    llvm_InitializeAArch64Target();
    llvm_InitializeAArch64TargetMC();
    llvm_InitializeAArch64AsmParser();
    llvm_InitializeAArch64AsmPrinter();
  }

  func new(): llvm_holder{
    llvm_holder::init_llvm();
    //printDefaultTargetAndDetectedCPU();
    let target_triple = getDefaultTargetTriple2();
    let env_triple = std::getenv("target_triple");
    if(env_triple.is_some()){
      target_triple.drop();
      target_triple = env_triple.unwrap().owned().cstr();
    }
    //print("target_triple2={}\n", target_triple);
    let target_machine = createTargetMachine(target_triple.ptr());
    return llvm_holder{target_triple: target_triple, target_machine: target_machine, di: Option<DebugInfo>::new()};

    //todo cache
  }

}

impl Compiler{

  func get_resolver(self): Resolver*{
    return *self.resolver.get();
  }

  func unit(self): Unit*{
    return &self.get_resolver().unit;
  }
  
  func get_all_methods(self): List<Method*>{
      let list = getMethods(self.unit());
      let resolver = self.get_resolver();
      for pair in &resolver.generated_methods{
        for m in pair.b{
          list.add(m.get());
        }
      }
      return list;
  }

  func compile(self, path: str): String{
    let outFile: String = get_out_file(path, self.config.out_dir.str());
    if(!self.cache.need_compile(path, outFile.str())){
      //todo inc check
      return outFile;
    }
    let ext = Path::ext(path);
    if (!ext.eq("x")) {
      panic("invalid extension for {}", path);
    }

    let resolv = self.ctx.create_resolver(path);
    self.resolver = Option::new(resolv);//Resolver*
    let resolver = self.get_resolver();
    resolver.resolve_all();
    self.llvm.initModule(path);
    self.createProtos();
    self.init_globals(self.config);
    
    let methods = getMethods(self.unit());
    for (let i = 0;i < methods.len();++i) {
      let m = *methods.get(i);
      self.genCode(m);
    }
    //generic methods from resolver
    for pair in &resolver.generated_methods{
      for m in pair.b{
        self.genCode(m.get());
      }
    }
    for p in &resolver.lambdas{
        self.genCode(p.b);
    }
    
    let name = getName(path);
    let llvm_file = format("{}/{}.ll", &self.ctx.out_dir, trimExtenstion(name));
    let llvm_file_cstr = llvm_file.cstr();
    emit_llvm(llvm_file_cstr.ptr());
    let outFile_cstr = CStr::new(outFile.clone());
    if(!self.config.llvm_only){
      emit_object(outFile_cstr.ptr(), self.llvm.target_machine, self.llvm.target_triple.ptr());
    }
    if(self.config.incremental_enabled || bootstrap){
      let oldpath = format("{}/{}.old", &self.ctx.out_dir, name);
      let newdata = File::read_string(path);
      if(File::exists(oldpath.str())){
        self.cache.inc.find_recompiles(self, path, oldpath.str());
      }
      File::write_string(newdata.str(), oldpath.str());
      oldpath.drop();
      newdata.drop();
    }
    self.cleanup();
    self.cache.update(path);
    self.cache.write_cache();

    self.ctx.prog.compile_done();

    methods.drop();
    llvm_file_cstr.drop();
    outFile_cstr.drop();
    return outFile;
  }

  func cleanup(self){
    self.NamedValues.clear();
  }

  func is_constexpr(expr: Expr*): bool{
    if let Expr::Lit(lit)=expr{
      return true;
    }
    return false;
  }

  func init_globals(self, config: CompilerConfig*){
    //make init func for global's rhs 
    let resolv = self.get_resolver();
    //declare external globals
    for gl_info in &resolv.glob_map{
      let ty = self.mapType(&gl_info.rt.type);
      let init = ptr::null<Constant>();
      let name_c = gl_info.name.clone().cstr();
      let glob = make_global(name_c.ptr(), ty, init);
      self.globals.add(gl_info.name.clone(), glob as Value*);
      name_c.drop();
    }
    let globals = resolv.unit.get_globals();
    if(globals.empty()){
      globals.drop();
      return;
    }
    let proto_pr = self.make_init_proto(resolv.unit.path.str());
    let proto = proto_pr.a;
    setSection(proto, ".text.startup".ptr());
    let bb = create_bb2(proto);
    SetInsertPoint(bb);
    let method = Method::new(Node::new(0), proto_pr.b, Type::new("void"));
    method.body = Option::new(Block::new(0, 0));
    self.own = Option::new(Own::new(self, &method));
    let globs = vector_Metadata_new();
    self.protos.get().cur = Option::new(proto);
    self.llvm.di.get().dbg_func(&method, proto, self);
    for(let j = 0;j < globals.len();++j){
      let gl: Global* = *globals.get(j);
      let rt = resolv.visit(&gl.expr);
      let ty = self.mapType(&rt.type);
      let init = self.make_global_init(gl, &rt, ty);
      let name_c = gl.name.clone().cstr();
      let glob: GlobalVariable* = make_global(name_c.ptr(), ty, init);
      name_c.drop();
      if(self.llvm.di.get().debug){
        let gve = self.llvm.di.get().dbg_glob(gl, &rt.type, glob, self);
        vector_Metadata_push(globs, gve as Metadata*);
      }
      self.globals.add(gl.name.clone(), glob as Value*);
      //todo make allochelper visit only children
      AllocHelper::new(self).visit(&gl.expr);
      self.emit_expr(&gl.expr,  glob as Value*);
      rt.drop();
    }
    if(self.llvm.di.get().debug){
      replaceGlobalVariables(self.llvm.di.get().cu, globs);
    }
    
    let struct_elem_types = vector_Type_new();
    vector_Type_push(struct_elem_types, getInt(32));
    vector_Type_push(struct_elem_types, getPtr());
    vector_Type_push(struct_elem_types, getPtr());
    let ctor_elem_ty = make_struct_ty_noname(struct_elem_types);
    let ctor_ty = getArrTy(ctor_elem_ty as llvm_Type*, 1);
    let struct_elems = vector_Constant_new();
    vector_Constant_push(struct_elems, makeInt(65535, 32) as Constant*);
    vector_Constant_push(struct_elems, proto as Constant*);
    vector_Constant_push(struct_elems, ConstantPointerNull_get(getPointerTo(getInt(32))) as Constant*);
    let ctor_init_struct = ConstantStruct_get_elems(ctor_elem_ty, struct_elems);
    let elems = vector_Constant_new();
    vector_Constant_push(elems, ctor_init_struct);
    let ctor_init = ConstantArray_get(ctor_ty, elems);
    let ctor = make_global_linkage("llvm.global_ctors".ptr(), ctor_ty as llvm_Type*, ctor_init, GlobalValue_appending());
    CreateRetVoid();
    self.own.reset();
    self.llvm.di.get().finalize();
    verifyFunction(proto);
    vector_Constant_delete(elems);
    vector_Constant_delete(struct_elems);
    vector_Metadata_delete(globs);
    vector_Type_delete(struct_elem_types);
    method.drop();
    globals.drop();
  }

  func make_global_init(self, gl: Global*, rt: RType*, ty: llvm_Type*): Constant*{
    let resolv = self.get_resolver();
    let init = ptr::null<Constant>();
    if(is_constexpr(&gl.expr)){
      if(rt.type.is_prim()){
        let rhs_str = gl.expr.print();
        if(rhs_str.eq("true")){
          init =  makeInt(1, 8) as Constant*;
        }else if(rhs_str.eq("false")){
          init =  makeInt(0, 8) as Constant*;
        }else{
          init = makeInt(i64::parse(rhs_str.str()).unwrap(), self.getSize(&rt.type) as i32) as Constant*;
        }
        rhs_str.drop();
      }else if(rt.type.is_str()){
        let val = is_str_lit(&gl.expr).unwrap().str();
        let slice_ty = self.protos.get().std("slice");
        let cons_elems = vector_Constant_new();
        let cons_elems_slice = vector_Constant_new();
        let ptr = self.get_global_string(val.str());
        vector_Constant_push(cons_elems_slice, ptr as Constant*);
        vector_Constant_push(cons_elems_slice, makeInt(val.len(), SLICE_LEN_BITS()) as Constant*);
        let cons_slice = ConstantStruct_get_elems(slice_ty, cons_elems_slice);
        vector_Constant_push(cons_elems, cons_slice);
        init = ConstantStruct_get_elems(ty as StructType*, cons_elems);
        
        vector_Constant_delete(cons_elems);
        vector_Constant_delete(cons_elems_slice);
      }else{
        panic("glob constexpr not supported: {:?}", gl);
      }
    }else{
      if(is_struct(&rt.type)){
        init = ConstantStruct_get(ty as StructType*);
      }else{
        //prim or ptr
        init = makeInt(0, self.getSize(&rt.type) as i32) as Constant*;
      }
    }
    return init;
  }

  //make all struct decl & method decl used by this module
  func createProtos(self){
    self.protos = Option::new(Protos::new(self));
    let p = self.protos.get();
    self.make_decl_protos();
    //methods
    let methods: List<Method*> = getMethods(self.unit());
    //print("local m\n");
    for (let i = 0;i < methods.len();++i) {
      let m = *methods.get(i);
      p.make_proto(m);
    }
    methods.drop();
    //generic methods from resolver
    //print("gen m\n");
    let r = self.get_resolver();
    for pair in &r.generated_methods{
        for m in pair.b{
          p.make_proto(m.get());
        }
    }
    //print("used m\n");
    for pr in &r.used_methods{
        p.make_proto(*pr.b);
    }
    for pair in &r.lambdas{
        p.make_proto(pair.b);
    }
  }
  
  func is_frame_call(self, m: Method*): bool{
    return m.name.eq("enter_frame") || m.name.eq("exit_frame") || m.name.eq("print_frame");
  }
  func exit_frame(self){
    let m = *self.curMethod.get();
    if(self.ctx.stack_trace && !self.is_frame_call(m)){
      let stmt = parse_stmt("exit_frame();".str(), &self.get_resolver().unit, m.line);
      self.visit(&stmt);
      stmt.drop();
    }
  }
  func enter_frame(self){
    let m = *self.curMethod.get();
    if(self.ctx.stack_trace && !self.is_frame_call(m)){
      let pretty = printMethod(m);
      let str = format("enter_frame(\"{} {}:{}\");", pretty, m.path, m.line);
      let stmt = parse_stmt(str, &self.get_resolver().unit, m.line);
      AllocHelper::new(self).visit(&stmt);
      self.visit(&stmt);
      pretty.drop();
      stmt.drop();
    }
  }
  func print_frame(self){
    let m = *self.curMethod.get();
    if(self.ctx.stack_trace && !self.is_frame_call(m)){
      let stmt = parse_stmt("print_frame();".str(), self.unit(), m.line);
      self.visit(&stmt);
      stmt.drop();
    }
  }

  func genCode(self, m: Method*){
    //print("gen {}\n", m.name);
    if(m.body.is_none()) return;
    if(m.is_generic) return;
    self.ctx.prog.compile_begin(m);
    self.curMethod = Option<Method*>::new(m);
    self.own.drop();
    self.own = Option::new(Own::new(self, m));
    let proto = self.protos.get().get_func(m);
    self.protos.get().cur = Option::new(proto);
    self.NamedValues.clear();
    let bb = create_bb2(proto);
    SetInsertPoint(bb);
    self.llvm.di.get().dbg_func(m, proto, self);
    AllocHelper::makeLocals(self, m.body.get());
    self.allocParams(m);
    self.enter_frame();
    self.storeParams(m, proto);

    let blk_val = self.visit_block(m.body.get());
    //dbg(m.name.eq("handle"), 51);
    let exit = Exit::get_exit_type(m.body.get());
    if(!exit.is_exit()){
      if(m.type.is_void()){
        self.own.get().do_return(m.body.get().end_line);
        self.exit_frame();
        if(is_main(m)){
          CreateRet(makeInt(0, 32) as Value*);
        }else{
          CreateRetVoid();
        }
      }else if(blk_val.is_some() && !m.type.is_void()){
        //setField(blk_val.unwrap(), &m.type, );
        self.visit_ret(blk_val.unwrap());
        self.own.get().do_move(m.body.get().return_expr.get());
      }
    }
    self.llvm.di.get().finalize();
    verifyFunction(proto);
    self.own.drop();
    self.own = Option<Own>::new();
    self.ctx.prog.compile_end(m);
    exit.drop();
  }
  
  func allocParams(self, m: Method*){
    let p = self.protos.get();
    let ff = p.get_func(m);
    if (m.self.is_some()) {
        let prm = m.self.get();
        self.alloc_prm(prm);
    }
    for (let i = 0;i < m.params.len();++i) {
        let prm = m.params.get(i);
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
    let ptr = *self.NamedValues.get(&prm.name).unwrap();
    let val = get_arg(f, argIdx) as Value*;
    if(is_struct(&prm.type)){
      self.copy(ptr, val, &prm.type);
    }else{
      CreateStore(val, ptr);
    }
    self.own.get().add_prm(prm, ptr);
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
      let prm = m.params.get(i);
      self.store_prm(prm, f, argIdx);
      self.llvm.di.get().dbg_prm(prm, argNo, self);
      ++argIdx;
      ++argNo;
    }
  }
  
  func get_alloc(self, e: Expr*): Value*{
    let ptr = self.allocMap.get(&e.id);
    if(ptr.is_none()){
      self.get_resolver().err(e, "get_alloc() not set");
    }
    return *ptr.unwrap();
  }
  func get_alloc(self, id: i32): Value*{
    let ptr = self.allocMap.get(&id);
    if(ptr.is_none()){
      panic("get_alloc() not set");
    }
    return *ptr.unwrap();
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
    let res = rt.type.clone();
    rt.drop();
    return res;
  }

  func compile_single(config: CompilerConfig): String{
    config.use_cache = false;
    File::create_dir(config.out_dir.str());
    let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
    for inc_dir in &config.src_dirs{
      ctx.add_path(inc_dir.str());
    }
    let cache = Cache::new(&config);
    let cmp = Compiler::new(ctx, &config, &cache);
    let compiled = List<String>::new();
    if(cmp.ctx.verbose){
      print("compiling {}\n", config.trim_by_root(config.file.str()));
    }
    let obj = cmp.compile(config.file.str());
    compiled.add(obj);
    let res = config.link(&compiled);
    config.drop();
    cmp.drop();
    compiled.drop();
    cache.drop();
    return res;
  }

  func compile_dir(config: CompilerConfig): String{
    if(config.jobs > 1){
      return Compiler::compile_dir_thread2(config);
    }
    let env_triple = std::getenv("target_triple");
    if(env_triple.is_some()){
      print("triple={}\n", env_triple.get());
    }
    File::create_dir(config.out_dir.str());
    let cache = Cache::new(&config);
    cache.read_cache();
    
    let inc = Incremental::new(&config);
    let src_dir = &config.file;
    let list: List<String> = File::list(src_dir.str(), Option::new(".x"), true);
    let compiled = List<String>::new();
    for(let i = 0;i < list.len();++i){
      let name = list.get(i).str();
      if(!name.ends_with(".x")) continue;
      let file: String = format("{}/{}", src_dir, name);
      if(File::is_dir(file.str())) {
        file.drop();
        continue;
      }
      let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
      ctx.verbose_all = config.verbose_all;
      for(let j = 0;j < config.src_dirs.len();++j){
        ctx.add_path(config.src_dirs.get(j).str());
      }
      let cmp = Compiler::new(ctx, &config, &cache);
      if(cmp.ctx.verbose){
        print("compiling [{}/{}] {}\n", i + 1, list.len(), config.trim_by_root(file.str()));
      }
      let obj = cmp.compile(file.str());
      compiled.add(obj);
      cmp.drop();
      file.drop();
    }
    for rec_file in &cache.inc.recompiles{
      let file: String = format("{}/{}", src_dir, rec_file);
      print("recompiling {}\n", config.trim_by_root(file.str()));
      //rem output to trigger recompiling
      File::remove_file(get_out_file(file.str(), config.out_dir.str()).str());
      let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
      ctx.verbose_all = config.verbose_all;
      for(let j = 0;j < config.src_dirs.len();++j){
        ctx.add_path(config.src_dirs.get(j).str());
      }
      let cmp = Compiler::new(ctx, &config, &cache);
      let obj = cmp.compile(file.str());
      //compiled.add(obj);
      cmp.drop();
      file.drop();
    }
    list.drop();
    cache.drop();
    inc.drop();
    return config.link(&compiled);
  }
 
  
  func compile_dir_thread2(config: CompilerConfig): String{
    let env_triple = std::getenv("target_triple");
    if(env_triple.is_some()){
      print("triple={}\n", env_triple.get());
    }
    File::create_dir(config.out_dir.str());
    let cache = Cache::new(&config);
    cache.read_cache();
    let src_dir = &config.file;
    let list: List<String> = File::list(src_dir.str(), Option::new(".x"), true);
    let compiled = Mutex::new(List<String>::new());
    let worker = Worker::new(config.jobs);
    for(let i = 0;i < list.len();++i){
      let name = list.get(i).str();
      let file: String = format("{}/{}", src_dir, name);
      if(File::is_dir(file.str()) || !name.ends_with(".x")) {
        file.drop();
        continue;
      }
      let idx = Mutex::new(0);
      let args = CompileArgs{
        file: file.clone(),
        config: &config,
        cache: &cache,
        compiled: &compiled,
        idx: &idx,
        len: list.len() as i32,
      };
      worker.add_arg(Compiler::make_compile_job2, args);
    }
    sleep(1);
    worker.join();
    list.drop();
    cache.drop();
    let comp = compiled.unwrap();
    return config.link(&comp);
  }

  func make_compile_job2(arg: c_void*){
    let args = arg as CompileArgs*;
    let config = args.config;
    let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
    for dir in &config.src_dirs{
      ctx.add_path(dir.str());
    }
    let cmp = Compiler::new(ctx, config, args.cache);
    let cmd = format("{} c -out {} -stdpath {} -nolink -cache {}", root_exe.get(), args.config.out_dir, args.config.std_path.get(), args.file);
    for inc_dir in &args.config.src_dirs{
        cmd.append(" -i ");
        cmd.append(inc_dir);
    }
    if(cmp.ctx.verbose){
        let idx = args.idx.lock();
        print("compiling [{}/{}] {}\n", *idx + 1, args.len, config.trim_by_root(args.file.str()));
        *idx = *idx + 1;
        args.idx.unlock();
    }
    let proc = Process::run(cmd.str());
    proc.eat_close();
    if(cmp.ctx.verbose){
        let compiled = args.compiled.lock();
        print("compiled [{}/{}] {}\n", compiled.len() + 1, args.len, config.trim_by_root(args.file.str()));
        args.compiled.unlock();
    }
    let compiled = args.compiled.lock();
    compiled.add(format("{}", get_out_file(args.file.str(), config.out_dir.str())));
    args.compiled.unlock();
    sleep(1);
    cmp.drop();
    cmd.drop();
  }

  func build_library(compiled: List<String>*, name: str, out_dir: str, is_shared: bool): String{
    File::create_dir(out_dir);
    let cmd = "".str();
    if(is_shared){
      cmd.append(get_linker());
      cmd.append("-shared -o ");
    }else{
      cmd.append("ar rcs ");
    }
    let out_file = format("{}/{}", out_dir, name);
    print("linking {}\n", out_file);
    cmd.append(&out_file);
    cmd.append(" ");
    for file in compiled{
      cmd.append(file.str());
      cmd.append(" ");
    }
  
    let cmd_s = cmd.cstr();
    if(system(cmd_s.ptr()) == 0){
      print("build library {}\n", out_file);
    }else{
      panic("link failed '{}'", cmd_s.get());
    }
    cmd_s.drop();
    return out_file;
  }
  
  func link(compiled: List<String>*, out_dir: str, name: str, args: str): String{
    let out_file = format("{}/{}", out_dir, name);
    print("linking {}\n", out_file);
    if(File::exist(out_file.str())){
      File::remove_file(out_file.str());
    }
    File::create_dir(out_dir);
    let cmd = get_linker().str();
    cmd.append(" -o ");
    cmd.append(&out_file);
    cmd.append(" ");
    for obj_file in compiled{
      cmd.append(obj_file.str());
      cmd.append(" ");
    }
    cmd.append(args);
    File::write_string(cmd.str(), format("{}/link.sh", out_dir).str());
    let cmd_s = cmd.cstr();
    if(system(cmd_s.ptr()) == 0){
      //run if linked
      print("build binary {}\n", out_file);
    }else{
      panic("link failed '{}'", cmd_s);
    }
    cmd_s.drop();
    return out_file;
  }
  
  func run(path: String){
    let path_c: CStr = path.cstr();
    let code = system(path_c.ptr());
    if(code != 0){
      print("error while running {} code={}\n", path_c, code);
      exit(1);
    }
    path_c.drop();
  }
}//Compiler


struct CompileArgs{
  file: String;
  config: CompilerConfig*;
  cache: Cache*;
  compiled: Mutex<List<String>>*;
  idx: Mutex<i32>*;
  len: i32;
}

impl CompilerConfig{
  func new(): CompilerConfig{
    return CompilerConfig::new(Option<String>::new());
  }
  func new(std_path: String): CompilerConfig{
    return CompilerConfig::new(Option<String>::new(std_path));
  }
  func new(std_path: Option<String>): CompilerConfig{
    return CompilerConfig{
      file: "".str(),
      src_dirs: List<String>::new(),
      out_dir: "".str(),
      args: "".str(),
      lt: LinkType::None,
      std_path: std_path,
      root_dir: Option<String>::new(),
      jobs: 1,
      verbose_all: false,
      incremental_enabled: false,
      use_cache: true,
      llvm_only: false,
    };
  }
  func set_std(self, std_path: String): CompilerConfig*{
    self.std_path.drop();
    self.std_path = Option::new(std_path);
    return self;
  }
  func set_std_path(self, std_path: str): CompilerConfig*{
    self.std_path.drop();
    self.std_path = Option::new(std_path.str());
    return self;
  }
  func set_out(self, out: str): CompilerConfig*{
    return self.set_out(out.str());
  }
  func set_out(self, out: String): CompilerConfig*{
    self.out_dir.drop();
    self.out_dir = out;
    return self;
  }
  func add_dir(self, dir: str): CompilerConfig*{
    self.src_dirs.add(dir.str());
    return self;
  }
  func add_dir(self, dir: String): CompilerConfig*{
    self.src_dirs.add(dir);
    return self;
  }
  func set_link(self, lt: LinkType): CompilerConfig*{
    self.lt = lt;
    return self;
  }
  func set_file(self, file: str): CompilerConfig*{
    return self.set_file(file.str());
  }
  func set_file(self, file: String): CompilerConfig*{
    self.file.drop();
    self.file = file;
    return self;
  }
  func set_jobs(self, j: i32): CompilerConfig*{
    self.jobs = j;
    return self;
  }
  func link(self, compiled: List<String>*): String{
    if(self.llvm_only) return "".owned();
    match &self.lt{
      LinkType::None => return "".owned(),
      LinkType::Binary(bin_name, args, run) => {
        let path = Compiler::link(compiled, self.out_dir.str(), bin_name.str(), args.str());
        if(*run){
          Compiler::run(path.clone());
        }
        return path;
      },
      LinkType::Static(lib_name) => {
        return Compiler::build_library(compiled, lib_name.str(), self.out_dir.str(), false);
      },
      LinkType::Dynamic(lib_name) => {
        return Compiler::build_library(compiled, lib_name.str(), self.out_dir.str(), true);
      },
    }
  }
  func trim_by_root(self, path: str): str{
    if(self.root_dir.is_none()){
      return path;
    }
    let root = self.root_dir.get();
    if(path.starts_with(root.str())){
      let res = path.substr(root.len());
      if(res.starts_with("/")){
        return res.substr(1, res.len());
      }
    }
    return path;
  }
}