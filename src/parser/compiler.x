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
import std/map
import std/io
import std/libc
import std/stack

static bootstrap = false;
static inline_rvo = false;

func get_linker(): str{
  let opt = getenv2("LD");
  if(opt.is_some()){
    return opt.unwrap();
  }
  return "clang-16";
}

struct Compiler{
  ctx: Context;
  resolver: Option<Resolver*>;
  main_file: Option<String>;
  llvm: llvm_holder;
  protos: Option<Protos>;
  NamedValues: Map<String, Value*>;
  globals: Map<String, Value*>;
  allocMap: Map<i32, Value*>;
  curMethod: Option<Method*>;
  loops: List<BasicBlock*>;
  loopNext: List<BasicBlock*>;
  own: Option<Own>;
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
  classMap: Map<String, llvm_Type*>;
  funcMap: Map<String, Function*>;
  libc: Map<str, Function*>;
  stdout_ptr: Value*;
  std: Map<str, StructType*>;
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
      classMap: Map<String, llvm_Type*>::new(),
      funcMap: Map<String, Function*>::new(),
      libc: Map<str, Function*>::new(),
      stdout_ptr: make_stdout(),
      std: Map<str, StructType*>::new(),
      cur: Option<Function*>::new(),
      compiler: compiler
    };
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
    let res = self.get(&name);
    name.drop();
    return res;
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
  /*func get_func(self, mangled: String*): Function*{
    let opt = self.funcMap.get_ptr(mangled);
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
    let opt = self.funcMap.get_ptr(&mangled);
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
    
    //printDefaultTargetAndDetectedCPU();
    let target_triple = getDefaultTargetTriple2();
    let env_triple = getenv2("target_triple");
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
  func new(ctx: Context): Compiler{
    let vm = llvm_holder::new();
    return Compiler{ctx: ctx,
     resolver: Option<Resolver*>::None,
     main_file: Option<String>::new(),
     llvm: vm,
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

  func compile(self, path: str, cache: Cache*, config: CompilerConfig*): String{
    /*if(bootstrap && path.ends_with("stmt_emitter.x")){
      drop_enabled = true;
    }*/
    let outFile: String = get_out_file(path, self);
    if(!cache.need_compile(path, outFile.str())){
      return outFile;
    }
    let ext = Path::ext(path);
    if (!ext.eq("x")) {
      panic("invalid extension for {}", path);
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
    let resolver = self.get_resolver();
    resolver.resolve_all();
    self.llvm.initModule(path);
    self.createProtos();
    self.init_globals(config);
    
    let methods = getMethods(self.unit());
    for (let i = 0;i < methods.len();++i) {
      let m = *methods.get_ptr(i);
      self.genCode(m);
    }
    //generic methods from resolver
    for (let i = 0;i < resolver.generated_methods.len();++i) {
        let m = resolver.generated_methods.get_ptr(i).get();
        self.genCode(m);
    }
    methods.drop();
    
    let name = getName(path);
    let llvm_file = format("{}/{}-bt.ll", &self.ctx.out_dir, trimExtenstion(name));
    let llvm_file_cstr = llvm_file.cstr();
    emit_llvm(llvm_file_cstr.ptr());
    /*if(self.ctx.verbose){
      print("writing {}\n", llvm_file_cstr);
    }*/
    llvm_file_cstr.drop();
    let outFile_cstr = CStr::new(outFile.clone());
    emit_object(outFile_cstr.ptr(), self.llvm.target_machine, self.llvm.target_triple.ptr());
    /*if(self.ctx.verbose){
      print("writing {}\n", outFile_cstr);
    }*/
    outFile_cstr.drop();
    self.cleanup();
    cache.update(path);
    cache.write_cache();
    return outFile;
  }

  func cleanup(self){
    self.NamedValues.clear();
  }

  func is_constexpr(expr: Expr*): bool{
    if let Expr::Lit(lit*)=(expr){
      return true;
    }
    return false;
  }

  func init_globals(self, config: CompilerConfig*){
    let resolv = self.get_resolver();
    //external globals
    for(let i = 0;i < resolv.glob_map.len();++i){
      let gl_info = resolv.glob_map.get_ptr(i);
      let ty = self.mapType(&gl_info.rt.type);
      let init = ptr::null<Constant>();
      let name_c = gl_info.name.clone().cstr();
      let glob = make_global(name_c.ptr(), ty, init);
      self.globals.add(gl_info.name.clone(), glob as Value*);
      name_c.drop();
    }
    if(self.get_resolver().unit.globals.empty()){
      return;
    }
    let proto = self.make_init_proto(resolv.unit.path.str());
    setSection(proto, ".text.startup".ptr());
    let bb = create_bb2(proto);
    SetInsertPoint(bb);
    let method = Method::new(Node::new(0), Compiler::mangle_static(resolv.unit.path.str()), Type::new("void"));
    method.body = Option::new(Block::new(0, 0));
    self.own = Option::new(Own::new(self, &method));
    let globs = vector_Metadata_new();
    self.protos.get().cur = Option::new(proto);
    for(let j = 0;j < resolv.unit.globals.len();++j){
      let gl: Global* = resolv.unit.globals.get_ptr(j);
      let rt = resolv.visit(&gl.expr);
      let ty = self.mapType(&rt.type);
      let init = ptr::null<Constant>();
      if(is_constexpr(&gl.expr)){
        if(rt.type.is_prim()){
          let rhs_str = gl.expr.print();
          if(rhs_str.eq("true")){
            init =  makeInt(1, 8) as Constant*;
          }else if(rhs_str.eq("false")){
            init =  makeInt(0, 8) as Constant*;
          }else{
            init = makeInt(i64::parse(rhs_str.str()), self.getSize(&rt.type) as i32) as Constant*;
          }
          rhs_str.drop();
        }else if(rt.type.is_str()){
          let val = is_str_lit(&gl.expr).unwrap().str();
          let slice_ty = self.protos.get().std("slice");
          let cons_elems = vector_Constant_new();
          let cons_elems_slice = vector_Constant_new();
          let val_c = CStr::new(val);
          let ptr = CreateGlobalStringPtr(val_c.ptr());
          val_c.drop();
          vector_Constant_push(cons_elems_slice, ptr as Constant*);
          vector_Constant_push(cons_elems_slice, makeInt(val.len(), 64) as Constant*);
          let cons_slice = ConstantStruct_get_elems(slice_ty, cons_elems_slice);
          vector_Constant_push(cons_elems, cons_slice);
          init = ConstantStruct_get_elems(ty as StructType*, cons_elems);
          
          vector_Constant_delete(cons_elems);
          vector_Constant_delete(cons_elems_slice);
        }else{
          panic("glob constexpr not supported: {}", gl);
        }
      }else{
        if(is_struct(&rt.type)){
          init = ConstantStruct_get(ty as StructType*);
        }else{
          init =  makeInt(0, self.getSize(&rt.type) as i32) as Constant*;
        }
      }
      let name_c = gl.name.clone().cstr();
      let glob: GlobalVariable* = make_global(name_c.ptr(), ty, init);
      name_c.drop();
      let gve = self.llvm.di.get().dbg_glob(gl, &rt.type, glob, self);
      vector_Metadata_push(globs, gve as Metadata*);
      self.globals.add(gl.name.clone(), glob as Value*);
      if let Expr::Call(mc*)=(&gl.expr){
        self.visit_call2(&gl.expr, mc, Option::new(glob as Value*), rt);
      }else{
        if(!is_constexpr(&gl.expr)){
          if let Expr::Array(list*, size*)=(&gl.expr){
            self.llvm.di.get().dbg_func(&method, proto, self);
            AllocHelper{self}.visit(&gl.expr);
            self.visit_array(&gl.expr, list, size);
          }else{
            panic("glob rhs {}", gl);
          }
        }
        rt.drop();
      }
    }
    replaceGlobalVariables(self.llvm.di.get().cu, globs);
    vector_Metadata_delete(globs);
    
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
    method.drop();
    vector_Constant_delete(struct_elems);
    vector_Constant_delete(elems);
    self.own.drop();
    self.own = Option<Own>::new();
    vector_Type_delete(struct_elem_types);
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
      let m = methods.get(i);
      p.make_proto(m);
    }
    methods.drop();
    //generic methods from resolver
    //print("gen m\n");
    for (let i = 0;i < self.get_resolver().generated_methods.len();++i) {
        let m = self.get_resolver().generated_methods.get_ptr(i).get();
        p.make_proto(m);
    }
    //print("used m\n");
    for (let i = 0;i < self.get_resolver().used_methods.len();++i) {
        let m = self.get_resolver().used_methods.get(i);
        p.make_proto(m);
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
    self.curMethod = Option<Method*>::new(m);
    self.own.drop();
    self.own = Option::new(Own::new(self, m));
    let f = self.protos.get().get_func(m);
    self.protos.get().cur = Option::new(f);
    let bb = create_bb2(f);
    self.NamedValues.clear();
    SetInsertPoint(bb);
    self.llvm.di.get().dbg_func(m, f, self);
    AllocHelper::makeLocals(self, m.body.get());
    self.allocParams(m);
    self.enter_frame();
    self.storeParams(m,f);

    self.visit_block(m.body.get());
    let exit = Exit::get_exit_type(m.body.get());
    if(!exit.is_exit() && m.type.is_void()){
      self.own.get().do_return(m.body.get().end_line);
      self.exit_frame();
      if(is_main(m)){
        CreateRet(makeInt(0, 32));
      }else{
        CreateRetVoid();
      }
    }
    exit.drop();
    self.llvm.di.get().finalize();
    verifyFunction(f);
    self.own.drop();
    self.own = Option<Own>::new();
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
    let res = rt.type.clone();
    rt.drop();
    return res;
  }

  func build_library(compiled: List<String>*, name: str, out_dir: str, is_shared: bool): String{
    create_dir(out_dir);
    let cmd = "".str();
    if(is_shared){
      cmd.append(get_linker());
      cmd.append("-shared -o ");
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
    let path = format("{}/{}", out_dir, name);
    if(exist(path.str())){
      File::remove_file(path.str());
    }
    create_dir(out_dir);
    let cmd = get_linker().str();
    cmd.append(" -o ");
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

  func compile_single(config: CompilerConfig): String{
    create_dir(config.out_dir.str());
    let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
    for inc in &config.src_dirs{
      ctx.add_path(inc.str());
    }
    let cmp = Compiler::new(ctx);
    let compiled = List<String>::new();
    use_cache = false;
    let cache = Cache::new(config.out_dir.str());
    if(cmp.ctx.verbose){
      print("compiling {}\n", config.trim_by_root(config.file.str()));
    }
    let obj = cmp.compile(config.file.str(), &cache, &config);
    compiled.add(obj);
    let res = config.link(&compiled, &cmp);
    config.drop();
    cmp.drop();
    compiled.drop();
    cache.drop();
    return res;
  }

  func compile_dir(config: CompilerConfig): String{
    let env_triple = getenv2("target_triple");
    if(env_triple.is_some()){
      print("triple={}\n", env_triple.get());
    }
    create_dir(config.out_dir.str());
    let cache = Cache::new(config.out_dir.str());
    cache.read_cache();
    let src_dir = &config.file;
    let list: List<String> = list(src_dir.str(), Option::new(".x"), true);
    let compiled = List<String>::new();
    for(let i = 0;i < list.len();++i){
      let name = list.get_ptr(i).str();
      if(!name.ends_with(".x")) continue;
      let file: String = format("{}/{}", src_dir, name);
      if(is_dir(file.str())) {
        file.drop();
        continue;
      }
      let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
      for(let j = 0;j < config.src_dirs.len();++j){
        ctx.add_path(config.src_dirs.get_ptr(j).str());
      }
      let cmp = Compiler::new(ctx);
      if(cmp.ctx.verbose){
        print("compiling [{}/{}] {}\n", i + 1, list.len(), config.trim_by_root(file.str()));
      }
      let obj = cmp.compile(file.str(), &cache, &config);
      compiled.add(obj);
      cmp.drop();
      file.drop();
    }
    list.drop();
    cache.drop();
    if let LinkType::Binary(bin_name, args, run) = (&config.lt){
      let path = link(&compiled, config.out_dir.str(), bin_name, args);
      compiled.drop();
      if(run){
        Compiler::run(path.clone());
      }
      config.drop();
      return path;
    }
    else if let LinkType::Static(lib_name*) = (&config.lt){
      let res = Compiler::build_library(&compiled, lib_name.str(), config.out_dir.str(), false);
      compiled.drop();
      config.drop();
      return res;
    }else{
      config.drop();
      panic("compile_dir");
    }
  }
 
}//Compiler

enum LinkType{
  Binary(name: str, args: str, run: bool),
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
      root_dir: Option<String>::new()
    };
  }
  func set_std(self, std_path: String): CompilerConfig*{
    self.std_path.drop();
    self.std_path = Option::new(std_path);
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
  func set_std_path(self, std_path: str): CompilerConfig*{
    self.std_path.drop();
    self.std_path = Option::new(std_path.str());
    return self;
  }
  func link(self, compiled: List<String>*, cmp: Compiler*): String{
    if(self.lt is LinkType::None){
      return "".str();
    }
    if let LinkType::Binary(bin_name, args, run) = (&self.lt){
      if(cmp.main_file.is_none()){
        return "".str();
      }
      let path = Compiler::link(compiled, self.out_dir.str(), bin_name, args);
      if(run){
        Compiler::run(path.clone());
      }
      return path;
    }
    else if let LinkType::Static(lib_name*) = (&self.lt){
      let res = Compiler::build_library(compiled, lib_name.str(), self.out_dir.str(), false);
      return res;
    }else{
      panic("CompilerConfig::link");
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