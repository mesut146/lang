import std/map
import std/io
import std/libc
import std/stack
import std/any
import std/th
//import std/llist
import ast/ast
import ast/printer
import ast/utils
import ast/copier
import parser/resolver
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
import parser/llvm

static bootstrap = false;
static inline_rvo = false;

func get_linker(): str{
  let opt = std::getenv("LD");
  if(opt.is_some()){
    return opt.unwrap();
  }
  let arr = ["clang++-19", "clang++", "g++", "gcc"];
  for ld in &arr[0..arr.len()]{
    let res = Process::run(*ld).read_close();
    if(res.is_ok()){
      res.drop();
      return *ld;
    }
  }
  panic("can't find linker");
}

struct CompilerError{
  msg: String;
}
impl CompilerError{
  func new(msg: String): CompilerError{
    return CompilerError{msg};
  }
}

enum LinkType{
  Binary{name: String, args: String, run: bool},
  Static{name: String},
  Dynamic{name: String},
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
  debug: bool;
  opt_level: Option<String>;
  stack_trace: bool;
}

struct LoopInfo{
  begin_bb: LLVMOpaqueBasicBlock*;
  next_bb: LLVMOpaqueBasicBlock*;
}

struct Compiler{
  ctx: Context;
  resolver: Option<Resolver*>;
  di: Option<DebugInfo>;
  ll: Option<Emitter>;
  protos: Option<Protos>;
  NamedValues: HashMap<String, LLVMOpaqueValue*>;
  globals: HashMap<String, LLVMOpaqueValue*>;
  allocMap: HashMap<i32, LLVMOpaqueValue*>;
  curMethod: Option<Method*>;
  loops: List<LoopInfo>;
  own: Option<Own>;
  string_map: HashMap<String, LLVMOpaqueValue*>;
  config: CompilerConfig*;
  cache: Cache*;
}
impl Compiler{
  func new(ctx: Context, config: CompilerConfig*, cache: Cache*): Compiler{
    return Compiler{
      ctx: ctx,
      resolver: Option<Resolver*>::new(),
      di: Option<DebugInfo>::new(),
      ll: Option<Emitter>::new(),
      protos: Option<Protos>::new(),
      NamedValues: HashMap<String, LLVMOpaqueValue*>::new(),
      globals: HashMap<String, LLVMOpaqueValue*>::new(),
      allocMap: HashMap<i32, LLVMOpaqueValue*>::new(),
      curMethod: Option<Method*>::new(),
      loops: List<LoopInfo>::new(),
      own: Option<Own>::new(),
      string_map: HashMap<String, LLVMOpaqueValue*>::new(),
      config: config,
      cache: cache,
    };
  }
}

struct FunctionInfo{
  val: LLVMOpaqueValue*;
  ty: LLVMOpaqueType*;
}

struct Protos{
  classMap: HashMap<String, LLVMOpaqueType*>;
  funcMap: HashMap<String, FunctionInfo>;
  libc: HashMap<str, FunctionInfo>;
  stdout_ptr: LLVMOpaqueValue*;
  std: HashMap<str, LLVMOpaqueType*>;
  cur: Option<LLVMOpaqueValue*>;
  compiler: Compiler*;
}
impl Drop for Protos{
  func drop(*self){
    self.classMap.drop();
    self.funcMap.drop();
    self.libc.drop();
    self.std.drop();
  }
}

impl Protos{
  func new(compiler: Compiler*): Protos{
    let res = Protos{
      classMap: HashMap<String, LLVMOpaqueType*>::new(),
      funcMap: HashMap<String, FunctionInfo>::new(),
      libc: HashMap<str, FunctionInfo>::new(),
      stdout_ptr: compiler.ll.get().make_stdout(),
      std: HashMap<str, LLVMOpaqueType*>::new(),
      cur: Option<LLVMOpaqueValue*>::new(),
      compiler: compiler
    };
    res.init();
    return res;
  }
  func init(self){
      let ll = self.compiler.ll.get();
      let sliceType = make_slice_type(ll);
      self.std.add("slice", sliceType);
      self.libc.add("printf", make_printf(ll));
      self.libc.add("sprintf", make_sprintf(ll));
      self.libc.add("fflush", make_fflush(ll));
      self.libc.add("malloc", make_malloc(ll));
  }
  func get(self, d: Decl*): LLVMOpaqueType*{
    let name = d.type.print();
    let res = self.get(&name);
    name.drop();
    return res;
  }
  func get(self, name: String*): LLVMOpaqueType*{
    let res = self.classMap.get(name);
    return *res.unwrap();
  }
  func libc(self, nm: str): FunctionInfo*{
    return self.libc.get(&nm).unwrap();
  }
  func std(self, nm: str): LLVMOpaqueType*{
    return *self.std.get(&nm).unwrap();
  }
  func make_proto(self, m: Method*){
    if(m.is_generic) return;
    self.get_func(m);
  }
  func get_func(self, m: Method*): FunctionInfo{
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

func init_llvm(){
  LLVMInitializeAllTargetInfos();
  LLVMInitializeAllTargets();
  LLVMInitializeAllTargetMCs();
  LLVMInitializeAllAsmPrinters();
  LLVMInitializeAllAsmParsers();
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
    let name = getName(path);
    
    let resolv = self.ctx.create_resolver(path);
    self.resolver = Option::new(resolv);//Resolver*
    let resolver = self.get_resolver();
    resolver.resolve_all();
    init_llvm();
    self.ll = Option::new(Emitter::new(name));
    self.di = Option::new(DebugInfo::new(self.config.debug, path, self.ll.get()));

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
    
    let llvm_file = format("{}/{}.ll", &self.ctx.out_dir, trimExtenstion(name));
    let ign = std::getenv("XNOEMIT").is_some();
    if(ign) print("XNOEMIT set\n");
    if(self.config.opt_level.is_some()){
      if(!ign) self.ll.get().optimize_module_newpm(self.config.opt_level.get());
    }
    if(!ign) self.ll.get().emit_module(llvm_file.str());
    if(!self.config.llvm_only){
       if(!ign) self.ll.get().emit_obj(outFile.str());
    }
    if(self.config.incremental_enabled || bootstrap){
      let oldpath = format("{}/{}.old", &self.ctx.out_dir, name);
      let newdata = File::read_string(path)?;
      if(File::exists(oldpath.str())){
        self.cache.inc.find_recompiles(self, path, oldpath.str());
      }
      File::write_string(newdata.str(), oldpath.str())?;
      oldpath.drop();
      newdata.drop();
    }
    self.cleanup();
    self.cache.update(path);
    self.cache.write_cache();

    self.ctx.prog.compile_done();

    methods.drop();
    llvm_file.drop();
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
    let ll = self.ll.get();
    //declare external globals
    for gl_info in &resolv.glob_map{
      let ty = self.mapType(&gl_info.rt.type);
      let init = ptr::null<LLVMOpaqueValue>();
      let name_c = gl_info.name.clone().cstr();
      //let glob = make_global(name_c.ptr(), ty, init);
      let glob = LLVMAddGlobal(ll.module, ty, name_c.ptr());
      self.globals.add(gl_info.name.clone(), glob);
      name_c.drop();
    }
    let globals = resolv.unit.get_globals(true);
    if(globals.empty()){
      globals.drop();
      return;
    }
    if(std::getenv("TERMUX").is_some()){
      //todo fix and remove this
      let globfiles = format("{}/globals.txt", config.out_dir);
      let tmp = File::open(globfiles.str(), OpenMode::Append)?;
      tmp.write_string(resolv.unit.path.str())?;
      tmp.write_string("\n")?;
      tmp.close();
      globfiles.drop();
    }
    let proto_pr = self.make_init_proto(resolv.unit.path.str());
    let proto = proto_pr.a;
    //setSection(proto, ".text.startup".ptr());
    LLVMSetSection(proto, ".text.startup".ptr());
    // let bb = create_bb2(proto);
    // SetInsertPoint(bb);
    let bb = LLVMAppendBasicBlockInContext(ll.ctx, proto, "".ptr());
    LLVMPositionBuilderAtEnd(ll.builder, bb);
    let method = Method::new(Node::new(0), proto_pr.b, Type::new("void"));
    method.body = Option::new(Block::new(0, 0));
    self.own = Option::new(Own::new(self, &method));
    self.protos.get().cur = Option::new(proto);
    self.di.get().dbg_func(&method, proto, self);
    for(let j = 0;j < globals.len();++j){
      let gl: Global* = *globals.get(j);
      if(gl.expr.is_none()){
        //local extern
        let ty = self.mapType(gl.type.get());
        let init = ptr::null<LLVMOpaqueValue>();
        let name_c = gl.name.clone().cstr();
        let glob = LLVMAddGlobal(ll.module, ty, name_c.ptr());
        LLVMSetInitializer(glob, init);
        self.globals.add(gl.name.clone(), glob );
        name_c.drop();
        continue;
      }
      if(std::getenv("TERMUX").is_some()){
        let pr = self.protos.get().libc("printf");
        let args = [ll.glob_str("glob init %s::%s\n"), ll.glob_str(Path::name(self.unit().path.str())), ll.glob_str(gl.name.str())];
        let res = LLVMBuildCall2(ll.builder, pr.ty, pr.val, args.ptr(), args.len() as i32, "".ptr());
      }
      let rt = resolv.visit(gl.expr.get());
      let ty = self.mapType(&rt.type);
      let init = self.make_global_init(gl, &rt, ty);
      let name_c = gl.name.clone().cstr();
      let glob = LLVMAddGlobal(ll.module, ty, name_c.ptr());
      LLVMSetInitializer(glob, init);
      name_c.drop();
      if(self.di.get().debug){
        let gve = self.di.get().dbg_glob(gl, &rt.type, glob, self);
        //vector_Metadata_push(globs, gve as Metadata*);
      }
      self.globals.add(gl.name.clone(), glob);
      //todo make allochelper visit only children
      if(gl.expr.is_some()){
        AllocHelper::new(self).visit(gl.expr.get());
        self.emit_expr(gl.expr.get(),  glob);
      }
      rt.drop();
    }
    if(self.config.debug){
      //replaceGlobalVariables(self.di.get().cu, globs);
    }
    
    make_global_ctors2(proto, ll);

    LLVMBuildRetVoid(ll.builder);
    self.own.reset();
    self.di.get().finalize();
    ll.verify_func(proto);
    //vector_Metadata_delete(globs);
    method.drop();
    globals.drop();
  }

  func make_global_ctors2(proto: LLVMOpaqueValue*, ll: Emitter*){
    let struct_elem_types = [ptr::null<LLVMOpaqueType>(); 3];
    struct_elem_types[0] = ll.intTy(32);
    struct_elem_types[1] = LLVMPointerTypeInContext(ll.ctx, 0);
    struct_elem_types[2] = LLVMPointerTypeInContext(ll.ctx, 0);
    let ctor_elem_ty = LLVMStructTypeInContext(ll.ctx, struct_elem_types.ptr(), 3, LLVMBoolFalse());
    let struct_elems = [ptr::null<LLVMOpaqueValue>(); 3];
    struct_elems[0] = ll.makeInt(65535, 32);
    struct_elems[1] = proto;
    struct_elems[2] =  LLVMConstNull(ll.intPtr(32));
    let ctor_init_struct = LLVMConstStructInContext(ll.ctx, struct_elems.ptr(), 3, LLVMBoolFalse());
    let ctor_ty = LLVMArrayType(ctor_elem_ty, 1);
    let elems = [ctor_init_struct];
    let ctor_init = LLVMConstArray(ctor_elem_ty, elems.ptr(), 1);
    let ctor = LLVMAddGlobal(ll.module, ctor_ty, "llvm.global_ctors".ptr());
    LLVMSetInitializer(ctor, ctor_init);
    LLVMSetLinkage(ctor, LLVMLinkage::LLVMAppendingLinkage{}.int());
  }

  func make_global_init(self, gl: Global*, rt: RType*, ty: LLVMOpaqueType*): LLVMOpaqueValue*{
    let ll = self.ll.get();
    let resolv = self.get_resolver();
    let init = ptr::null<LLVMOpaqueValue>();
    if(gl.expr.is_none()) return init;
    if(is_constexpr(gl.expr.get())){
      if(rt.type.is_prim()){
        let rhs_str = gl.expr.get().print();
        if(rhs_str.eq("true")){
          init = ll.makeInt(1, 8);
        }else if(rhs_str.eq("false")){
          init = ll.makeInt(0, 8);
        }else{
          let val = i64::parse(rhs_str.str()).unwrap();
          init = ll.makeInt(val, self.getSize(&rt.type) as i32);
        }
        rhs_str.drop();
      }else if(rt.type.is_str()){
        let val = is_str_lit(gl.expr.get()).unwrap().str();
        let slice_ty = self.protos.get().std("slice");
        let ptr = self.get_global_string(val.str());
        let cons_elems_slice = [ptr, ll.makeInt(val.len(), SLICE_LEN_BITS())];
        let cons_slice = LLVMConstStructInContext(ll.ctx, cons_elems_slice.ptr(), 2, 0);
        let cons_elems = [cons_slice];
        init = LLVMConstStructInContext(ll.ctx, cons_elems.ptr(), 1, 0);
      }else{
        panic("glob constexpr not supported: {:?}", gl);
      }
    }else{
      if(is_struct(&rt.type)){
        //init = ConstantStruct_get(ty as StructType*);
        //init = LLVMConstStructInContext(ll.ctx, ty);
        init = LLVMConstNull(ty);
      }else{
        //prim or ptr
        init = ll.makeInt(0, self.getSize(&rt.type) as i32);
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
    if(self.config.stack_trace && !self.is_frame_call(m)){
      let stmt = parse_stmt("exit_frame();".str(), &self.get_resolver().unit, m.line);
      self.visit(&stmt);
      stmt.drop();
    }
  }
  func enter_frame(self){
    let m = *self.curMethod.get();
    if(self.config.stack_trace && !self.is_frame_call(m)){
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
    if(self.config.stack_trace && !self.is_frame_call(m)){
      let stmt = parse_stmt("print_frame();".str(), self.unit(), m.line);
      self.visit(&stmt);
      stmt.drop();
    }
  }

  func genCode(self, m: Method*){
    //print("gen {}\n", m.name);
    if(m.body.is_none()) return;
    if(m.is_generic) return;
    if(std::getenv("genCode").is_some()){
      let s = printMethod(m);
      print("emit {:?}\n", s);
      s.drop();
    }
    let ign = std::getenv("XNOEMIT").is_some();
    if(ign) return;
    self.ctx.prog.compile_begin(m);
    self.curMethod = Option<Method*>::new(m);
    self.own.drop();
    self.own = Option::new(Own::new(self, m));
    let proto = self.protos.get().get_func(m);
    self.protos.get().cur = Option::new(proto.val);
    self.NamedValues.clear();
    let ll = self.ll.get();
    let bb = LLVMAppendBasicBlockInContext(ll.ctx, proto.val, "entry".ptr());
    LLVMPositionBuilderAtEnd(ll.builder, bb);
    self.di.get().dbg_func(m, proto.val, self);
    AllocHelper::makeLocals(self, m.body.get());
    self.allocParams(m);
    self.enter_frame();
    self.storeParams(m, proto.val);

    let blk_val = self.visit_block(m.body.get());
    //dbg(m.name.eq("handle"), 51);
    let exit = Exit::get_exit_type(m.body.get());
    if(!exit.is_exit()){
      if(m.type.is_void()){
        self.own.get().do_return(m.body.get().end_line);
        self.exit_frame();
        if(is_main(m)){
          LLVMBuildRet(ll.builder, ll.makeInt(0, 32));
        }else{
          LLVMBuildRetVoid(ll.builder);
        }
      }else if(blk_val.is_some() && !m.type.is_void()){
        //setField(blk_val.unwrap(), &m.type, );
        self.visit_ret(blk_val.unwrap());
        self.own.get().do_move(m.body.get().return_expr.get());
      }
    }
    self.di.get().finalize();
    ll.verify_func(proto.val);
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
    let name_c = prm.name.clone().cstr();
    let ptr = LLVMBuildAlloca(self.ll.get().builder, ty, name_c.ptr());
    name_c.drop();
    self.NamedValues.add(prm.name.clone(), ptr);
  }

  func copy(self, trg: LLVMOpaqueValue*, src: LLVMOpaqueValue*, type: Type*){
    let size = self.getSize(type) / 8;
    LLVMBuildMemCpy(self.ll.get().builder, trg, 0, src, 0, self.ll.get().makeInt(size, 64));
  }

  func store_prm(self, prm: Param*, f: LLVMOpaqueValue*, argIdx: i32){
    let ptr = *self.NamedValues.get(&prm.name).unwrap();
    let val = LLVMGetParam(f, argIdx);
    if(is_struct(&prm.type)){
      self.copy(ptr, val, &prm.type);
    }else{
      LLVMBuildStore(self.ll.get().builder, val, ptr);
    }
    self.own.get().add_prm(prm, ptr);
  }

  func storeParams(self, m: Method*, f: LLVMOpaqueValue*){
    let argIdx = 0;
    if(is_struct(&m.type)){
      ++argIdx;//sret
    }
    let argNo = 1;
    if (m.self.is_some()) {
      let prm = m.self.get();
      self.store_prm(prm, f, argIdx);
      self.di.get().dbg_prm(prm, argNo, self);
      ++argIdx;
      ++argNo;
    }
    for(let i = 0;i < m.params.len();++i){
      let prm = m.params.get(i);
      self.store_prm(prm, f, argIdx);
      self.di.get().dbg_prm(prm, argNo, self);
      ++argIdx;
      ++argNo;
    }
  }
  
  func get_alloc(self, e: Expr*): LLVMOpaqueValue*{
    let ptr = self.allocMap.get(&e.id);
    if(ptr.is_none()){
      self.get_resolver().err(e, "get_alloc() not set");
    }
    return *ptr.unwrap();
  }
  func get_alloc(self, id: i32): LLVMOpaqueValue*{
    let ptr = self.allocMap.get(&id);
    if(ptr.is_none()){
      panic("get_alloc() not set");
    }
    return *ptr.unwrap();
  }

  func cur_func(self): LLVMOpaqueValue*{
    return self.protos.get().cur.unwrap();
  }

  func getType(self, e: Expr*): Type{
    let rt = self.get_resolver().visit_cached(e);
    let res = rt.type.clone();
    rt.drop();
    return res;
  }

  func compile_single(config: CompilerConfig): Result<String, CompilerError>{
    config.use_cache = false;
    File::create_dir(config.out_dir.str())?;
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

  func compile_dir(config: CompilerConfig): Result<String, CompilerError>{
    if(config.jobs > 0){
      return Compiler::compile_dir_thread(config);
    }
    File::create_dir(config.out_dir.str())?;
    let cache = Cache::new(&config);
    cache.read_cache();
    
    let inc = Incremental::new(&config);
    let src_dir = &config.file;
    let list: List<String> = File::read_dir(src_dir.str()).unwrap();
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
      File::remove_file(get_out_file(file.str(), config.out_dir.str()).str())?;
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
 
  
  func compile_dir_thread(config: CompilerConfig): Result<String, CompilerError>{
    File::create_dir(config.out_dir.str())?;
    let cache = Cache::new(&config);
    cache.read_cache();
    let src_dir = &config.file;
    let list: List<String> = File::read_dir(src_dir.str()).unwrap();
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
      worker.add_arg(Compiler::make_compile_job, args);
    }
    sleep(1);
    worker.join();
    list.drop();
    cache.drop();
    let comp = compiled.unwrap();
    return config.link(&comp);
  }

  func make_compile_job(arg: c_void*){
    let args = arg as CompileArgs*;
    let config = args.config;
    let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
    for dir in &config.src_dirs{
      ctx.add_path(dir.str());
    }
    let cmd = format("{} c -out {} -stdpath {} -nolink -cache", root_exe.get(), args.config.out_dir, args.config.std_path.get());
    for inc_dir in &args.config.src_dirs{
        cmd.append(" -i ");
        cmd.append(inc_dir);
    }
    if(config.opt_level.is_some()){
      cmd.append(" ");
      cmd.append(config.opt_level.get());
    }
    cmd.append(" ");
    cmd.append(&args.file);
    if(ctx.verbose){
      let idx = args.idx.lock();
      print("compiling {}\n", config.trim_by_root(args.file.str()));
      *idx = *idx + 1;
      args.idx.unlock();
    }
    let proc = Process::run(cmd.str());
    let code = proc.eat_close();
    if(code != 0){
      panic("failed to compile {}", args.file);
    }
    if(ctx.verbose){
      let idx = args.idx.lock();
      let compiled = args.compiled.lock();
      print("compiled [{}/{}] {}\n", compiled.len() + 1, args.len, config.trim_by_root(args.file.str()));
      args.compiled.unlock();
      args.idx.unlock();
    }
    let compiled = args.compiled.lock();
    compiled.add(format("{}", get_out_file(args.file.str(), config.out_dir.str())));
    args.compiled.unlock();
    sleep(1);
    ctx.drop();
    cmd.drop();
  }

  func build_library(compiled: List<String>*, name: str, out_dir: str, is_shared: bool): Result<String, CompilerError>{
    File::create_dir(out_dir)?;
    let cmd = "".str();
    if(is_shared){
      cmd.append(get_linker());
      cmd.append("-shared -o ");
    }else{
      cmd.append("ar rcs ");
    }
    let out_file = format("{}/{}", out_dir, name);
    //print("linking {}\n", out_file);
    cmd.append(&out_file);
    cmd.append(" ");
    for file in compiled{
      cmd.append(file.str());
      cmd.append(" ");
    }

    let cmd_res = Process::run(cmd.str()).read_close();
    if(cmd_res.is_err()){
      let res = Result<String, CompilerError>::err(CompilerError::new(format("link failed '{}'", cmd)));
      cmd.drop();
      return res;
    }
    print("build library {}\n", out_file);
    return Result<String, CompilerError>::ok(out_file);
  }
  
  func link(compiled: List<String>*, out_dir: str, name: str, args: str): Result<String, CompilerError>{
    let out_file = format("{}/{}", out_dir, name);
    //print("linking {}\n", out_file);
    if(File::exists(out_file.str())){
      File::remove_file(out_file.str())?;
    }
    File::create_dir(out_dir)?;
    let cmd = get_linker().str();
    cmd.append(" -o ");
    cmd.append(&out_file);
    cmd.append(" ");
    for obj_file in compiled{
      cmd.append(obj_file.str());
      cmd.append(" ");
    }
    cmd.append(args);
    //todo move this to main or bt.sh
    cmd.append(" -Wl,-rpath=$ORIGIN/../lib");
    File::write_string(cmd.str(), format("{}/link.sh", out_dir).str())?;
    let cmd_s = cmd.cstr();
    if(system(cmd_s.ptr()) == 0){
      print("build binary {}\n", out_file);
    }else{
      return Result<String, CompilerError>::err(CompilerError::new(format("link failed '{}'", cmd_s)));
    }
    cmd_s.drop();
    return Result<String, CompilerError>::ok(out_file);
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
      jobs: 0,
      verbose_all: false,
      incremental_enabled: false,
      use_cache: true,
      llvm_only: false,
      debug: false,
      opt_level: Option<String>::new(),
      stack_trace: false,
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
    if(j < 0){
      panic("invalid jobs {:?}", j);
    }
    self.jobs = j;
    return self;
  }
  func link(self, compiled: List<String>*): Result<String, CompilerError>{
    if(self.llvm_only) return Result<String, CompilerError>::ok("".owned());
    match &self.lt{
      LinkType::None => return Result<String, CompilerError>::ok("".owned()),
      LinkType::Binary(bin_name, args, run) => {
        let path = Compiler::link(compiled, self.out_dir.str(), bin_name.str(), args.str());
        if(path.is_ok() && *run){
          Compiler::run(path.get().clone());
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