import std/map
import std/io
import std/libc
import std/stack
import std/any
import std/th

import ast/ast
import ast/printer
import ast/utils
import ast/copier

import resolver/resolver
import resolver/derive

import parser/ownership
import parser/own_model
import parser/cache
import parser/incremental

import backend/bridge
import backend/compiler_helper
import backend/alloc_helper
import backend/debug_helper
import backend/stmt_emitter
import backend/expr_emitter
import backend/compiler


struct LoopInfo{
  begin_bb: BasicBlock*;
  next_bb: BasicBlock*;
}

struct Emitter{
  ctx: Context;
  resolver: Option<Resolver*>;
  di: Option<DebugInfo>;
  ll: Option<LLVMInfo>;
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
  //set when any emitted body carries `#[inline]`: only then is the
  //always-inline pass worth running (it walks every function in the module)
  inline_used: bool;
}
impl Emitter{
  func new(ctx: Context, config: CompilerConfig*, cache: Cache*): Emitter{
    return Emitter{
      ctx: ctx,
      resolver: Option<Resolver*>::new(),
      di: Option<DebugInfo>::new(),
      ll: Option<LLVMInfo>::new(),
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
      inline_used: false,
    };
  }
}

struct FunctionInfo{
  val: Function*;
  ty: llvm_FunctionType*;
}

struct Protos{
  classMap: HashMap<String, llvm_Type*>;
  funcMap: HashMap<String, FunctionInfo>;
  libc: HashMap<str, FunctionInfo>;
  stdout_ptr: Value*;
  std: HashMap<str, llvm_Type*>;
  cur: Option<Function*>;
  compiler: Emitter*;
}
//No manual Drop: derived glue frees the maps (all structural drop
//types); LLVM objects behind the pointers are process-lifetime and
//were never freed here either.

impl Protos{
  func new(compiler: Emitter*): Protos{
    let res = Protos{
      classMap: HashMap<String, llvm_Type*>::new(),
      funcMap: HashMap<String, FunctionInfo>::new(),
      libc: HashMap<str, FunctionInfo>::new(),
      stdout_ptr: compiler.ll.get().make_stdout(),
      std: HashMap<str, llvm_Type*>::new(),
      cur: Option<Function*>::new(),
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
  func get(self, d: Decl*): llvm_Type*{
    let name = d.type.print();
    let res = self.get(&name);
    return res;
  }
  func get(self, name: String*): llvm_Type*{
    let res = self.classMap.get(name);
    return *res.unwrap();
  }
  func libc(self, nm: str): FunctionInfo*{
    return self.libc.get(&nm).unwrap();
  }
  func std(self, nm: str): llvm_Type*{
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
      return self.compiler.make_proto(m).unwrap();
      //panic("no proto for {}, {}", mangled, demangle(mangled.str()));
    }
    return *opt.unwrap();
  }
}

impl Emitter{
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
    if (!Path::ext(path).eq("x")) {
      panic("invalid extension for {}", path);
    }
    let name = getName(path);
    let resolv = self.ctx.create_resolver(path);
    self.resolver = Option::new(resolv);//Resolver*
    let resolver = self.get_resolver();
    resolver.resolve_all();
    if(self.config.stack_trace){
      //genCode() below synthesizes `enter_frame("<sig> <path>:<line>")` for
      //every method (see Emitter::enter_frame), whose argument is a `str`
      //literal. Decl protos are demand-driven (resolver.used_types), so a unit
      //that never mentions `str` has none, and the AllocHelper pass over the
      //synthesized statement dies in mapType ("mapType2 str"). Record it
      //before protos are built. add_used_decl (not used_types.add) so the
      //decl's imports/drop glue come along, like any other used type.
      let str_rt = resolver.visit_type(&Type::new("str"));
      resolver.add_used_decl(resolver.get_decl(&str_rt).unwrap());
    }
 
    self.ll = Option::new(LLVMInfo::new(name));
    self.di = Option::new(DebugInfo::new(self.config.debug, self.config.display_path(path).str(), self.ll.get()));

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
    
    if(self.config.opt_level.is_some()){
      self.ll.get().optimize_module_newpm(self.config.opt_level.get());
    }else{
      //No -O, but still drop unreferenced linkonce definitions. A unit emits
      //a linkonce body for every generic instantiation and every drop/clone
      //glue method it instantiates (a large file: ~1700 of ~1900 functions),
      //and emitting an object for all of those whose only purpose is to be
      //available to *other* units is pure codegen work. Linkonce means a unit
      //that uses one emits its own copy, so discarding the unused ones here is
      //exactly the contract the linker relies on (and it makes the emitted
      //object smaller too).
      //`always-inline` first (honours `#[inline]`, which nothing else would
      //in a no--O build), then drop the bodies that became unreferenced. The
      //pass walks every function in the module, so only pay for it when a
      //body actually carries the attribute.
      //-O0.5: the emitter writes every local as an alloca + load/store (that
      //is what makes -O0 output slow, and what made `#[inline]` pointless: an
      //inlined body's allocas stayed on the stack). mem2reg promotes them to
      //SSA registers and deletes the loads/stores it replaces, dce drops what
      //is left. globaldce runs first so only live functions pay for promotion,
      //and again at the end to drop the bodies that inlining made unreferenced.
      //`instcombine` is deliberately absent: bare `instcombine` in a textual
      //pipeline aborts ("did not reach a fixpoint after 1 iterations"), and
      //mem2reg+dce already carry the win (handoff.md, batch 15).
      if(self.inline_used){
        self.ll.get().optimize_pipeline("globaldce,always-inline,mem2reg,dce,globaldce");
      }else{
        self.ll.get().optimize_pipeline("globaldce,mem2reg,dce");
      }
    }
    self.ll.get().emit_module(llvm_file.str());
    if(!self.config.llvm_only){
       self.ll.get().emit_obj(outFile.str());
    }
    if(self.config.incremental_enabled){
      let oldpath = format("{}/{}.old", &self.ctx.out_dir, name);
      let newdata = File::read_string(path)?;
      if(File::exists(oldpath.str())){
        self.cache.inc.find_recompiles(path, oldpath.str());
      }
      File::write_string(newdata.str(), oldpath.str())?;
    }
    self.cleanup();
    self.cache.update(path);
    self.cache.write_cache();

    self.ctx.prog.compile_done();

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
      let init = ptr::null<Value>();
      let name_c = gl_info.name.clone().cstr();
      let glob = make_global(ll.module, ty, init as Constant*, GlobalValue_ext(), name_c.ptr());
      self.globals.add(gl_info.name.clone(), glob as Value*);
    }
    let globals = resolv.unit.get_globals(true);
    if(globals.empty()){
      return;
    }
    if(std::getenv("TERMUX").is_some()){
      //todo fix and remove this
      let globfiles = format("{}/globals.txt", config.out_dir);
      let tmp = File::open(globfiles.str(), OpenMode::Append)?;
      tmp.write_string(resolv.unit.path.str())?;
      tmp.write_string("\n")?;
      tmp.close();
    }
    let proto_pr = self.make_init_proto(resolv.unit.path.str());
    let proto = proto_pr.a;
    setSection(proto, ".text.startup".ptr());
    let bb = create_bb(ll.ctx, "".ptr(), proto);
    SetInsertPoint(ll.builder, bb);
    let method = Method::new(Node::new(0), proto_pr.b, Type::new("void"));
    method.body = Option::new(Block::new(0, 0));
    self.own = Option::new(Own::new(self, &method));
    self.protos.get().cur = Option::new(proto);
    self.di.get().dbg_func(&method, proto, self);
    let globs = List<Metadata*>::new();
    for(let j = 0;j < globals.len();++j){
      let gl: Global* = *globals.get(j);
      if(gl.expr.is_none()){
        //local extern
        let ty = self.mapType(gl.type.get());
        let init = ptr::null<Constant>();
        let name_c = gl.name.clone().cstr();
        let glob = make_global(ll.module, ty, init, ext(), name_c.ptr());
        self.globals.add(gl.name.clone(), glob as Value*);
        continue;
      }
      if(std::getenv("TERMUX").is_some()){
        let pr = self.protos.get().libc("printf");
        let args = [ll.glob_str("glob init %s::%s\n"), ll.glob_str(Path::name(self.unit().path.str())), ll.glob_str(gl.name.str())];
        let res = CreateCall(ll.builder, pr.val, args.ptr(), args.len() as i32);
      }
      let rt = resolv.visit(gl.expr.get());
      let ty = self.mapType(&rt.type);
      let init = self.make_global_init(gl, &rt, ty);
      let name_c = gl.name.clone().cstr();
      let glob = make_global(ll.module, ty, init, GlobalValue_ext(), name_c.ptr());
      if(self.di.get().debug){
        let gve = self.di.get().dbg_glob(gl, &rt.type, glob as Value*, self);
        globs.add(gve as Metadata*);
      }
      self.globals.add(gl.name.clone(), glob as Value*);
      //todo make allochelper visit only children
      if(gl.expr.is_some()){
        AllocHelper::new(self).visit(gl.expr.get());
        self.emit_expr(gl.expr.get(),  glob as Value*);
      }
    }
    if(self.config.debug){
      replaceGlobalVariables(ll.ctx, self.di.get().cu, globs.ptr(), globs.len() as i32);
    }
    make_global_ctors(proto, ll);
    CreateRetVoid(ll.builder);
    self.own.reset();
    self.di.get().finalize();
    verifyFunction(proto);
  }

  func make_global_ctors(proto: Function*, ll: LLVMInfo*){
    let struct_elem_types = [ptr::null<llvm_Type>(); 3];
    struct_elem_types[0] = intTy(ll.ctx, 32);
    struct_elem_types[1] = getPtr(ll.ctx);
    struct_elem_types[2] = getPtr(ll.ctx);
    let ctor_elem_ty = make_struct_ty(ll.ctx, "".ptr(), struct_elem_types.ptr(), 3);

    let struct_elems = [ptr::null<Constant>(); 3];
    struct_elems[0] = ll.makeInt(65535, 32) as Constant*;
    struct_elems[1] = proto as Constant*;
    struct_elems[2] = ConstantPointerNull_get(ll.intPtr(32) as PointerType*) as Constant*;
    let ctor_init_struct = ConstantStruct_getAnon(struct_elems.ptr(), 3);

    let ctor_ty = ArrayType_get(ctor_elem_ty as llvm_Type*, 1);
    let elems = [ctor_init_struct];
    let ctor_init = ConstantArray_get(ctor_ty, elems.ptr(), 1);
    let ctor = make_global(ll.module, ctor_ty as llvm_Type*, ctor_init, GlobalValue_appending(), "llvm.global_ctors".ptr());
  }

  func make_global_init(self, gl: Global*, rt: RType*, ty: llvm_Type*): Constant*{
    let ll = self.ll.get();
    let resolv = self.get_resolver();
    let init = ptr::null<Constant>();
    if(gl.expr.is_none()) return init;
    if(is_constexpr(gl.expr.get())){
      if(rt.type.is_prim()){
        let rhs_str = gl.expr.get().print();
        if(rhs_str.eq("true")){
          init = ll.makeInt(1, 8) as Constant*;
        }else if(rhs_str.eq("false")){
          init = ll.makeInt(0, 8) as Constant*;
        }else{
          let val = i64::parse(rhs_str.str()).unwrap();
          init = ll.makeInt(val, self.getSize(&rt.type) as i32) as Constant*;
        }
      }else if(rt.type.is_str()){
        let val = is_str_lit(gl.expr.get()).unwrap().str();
        let slice_ty = self.protos.get().std("slice");
        let ptr = self.get_global_string(val.str());
        let cons_elems_slice = [ptr as Constant*, ll.makeInt(val.len(), SLICE_LEN_BITS()) as Constant*];
        let cons_slice = ConstantStruct_getAnon(cons_elems_slice.ptr(), 2);
        let cons_elems = [cons_slice as Constant*];
        init = ConstantStruct_getAnon(cons_elems.ptr(), 1) as Constant*;
      }else{
        panic("glob constexpr not supported: {:?}", gl);
      }
    }else{
      if(is_struct(&rt.type)){
        //init = ConstantPointerNull_get(getPointerTo(ty)) as Constant*;
        init = ConstantAggregateZero_get(ty) as Constant*;
      }else{
        //prim or ptr
        init = ll.makeInt(0, self.getSize(&rt.type) as i32) as Constant*;
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
    for (let i = 0;i < methods.len();++i) {
      let m = *methods.get(i);
      p.make_proto(m);
    }
    //generic methods from resolver
    let r = self.get_resolver();
    for pair in &r.generated_methods{
        for m in pair.b{
          p.make_proto(m.get());
        }
    }
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
    }
  }
  func enter_frame(self){
    let m = *self.curMethod.get();
    if(self.config.stack_trace && !self.is_frame_call(m)){
      let pretty = printMethod(m);
      let str = format("enter_frame(\"{} {}:{}\");", pretty, self.config.display_path(m.path.str()), m.line);
      let stmt = parse_stmt(str, &self.get_resolver().unit, m.line);
      AllocHelper::new(self).visit(&stmt);
      self.visit(&stmt);
    }
  }
  func print_frame(self){
    let m = *self.curMethod.get();
    if(self.config.stack_trace && !self.is_frame_call(m)){
      let stmt = parse_stmt("print_frame();".str(), self.unit(), m.line);
      self.visit(&stmt);
    }
  }

  func genCode(self, m: Method*){
    if(m.body.is_none()) return;
    if(m.is_generic) return;
    self.ctx.prog.compile_begin(m);
    self.curMethod = Option<Method*>::new(m);
    self.own = Option::new(Own::new(self, m));
    let proto = self.protos.get().get_func(m);
    if(m.attr.has_attr("inline")){
      //`#[inline]` means "inline this even when the build does no other
      //optimization": the -O0 pipeline runs LLVM's always-inliner, which
      //inlines exactly the functions carrying this attribute. At -O2 the
      //normal inliner would usually do it anyway; the attribute makes it
      //unconditional. Small std helpers (List::get, str::len, ...) are the
      //call sites this exists for.
      self.ll.get().add_fn_attr(proto.val, "alwaysinline");
      self.inline_used = true;
    }
    self.protos.get().cur = Option::new(proto.val);
    self.NamedValues.clear();
    let ll = self.ll.get();
    let bb = create_bb(ll.ctx, "entry".ptr(), proto.val);
    SetInsertPoint(ll.builder, bb);
    self.di.get().dbg_func(m, proto.val, self);
    AllocHelper::makeLocals(self, m.body.get());
    self.allocParams(m);
    self.enter_frame();
    self.storeParams(m, proto.val);

    let blk_val = self.visit_block(m.body.get());
    let exit = Exit::get_exit_type(m.body.get());
    if(!exit.is_exit()){
      if(m.type.is_void()){
        self.own.get().do_return(m.body.get().end_line);
        self.exit_frame();
        if(is_main(m)){
          CreateRet(ll.builder, ll.makeInt(0, 32));
        }else{
          CreateRetVoid(ll.builder);
        }
      }else if(blk_val.is_some() && !m.type.is_void()){
        //store(blk_val.unwrap(), &m.type, );
        self.visit_ret(blk_val.unwrap());
        self.own.get().do_move(m.body.get().return_expr.get());
      }
    }
    self.di.get().finalize();
    verifyFunction(proto.val);
    self.own = Option<Own>::new();
    self.ctx.prog.compile_end(m);
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
    let ptr = CreateAlloca(self.ll.get().builder, ty);
    Value_setName(ptr, name_c.ptr());
    self.NamedValues.add(prm.name.clone(), ptr);
  }

  func copy(self, trg: Value*, src: Value*, type: Type*){
    let size = self.getSize(type) / 8;
    CreateMemCpy(self.ll.get().builder, trg, src, size);
  }

  func store_prm(self, prm: Param*, f: Function*, argIdx: i32){
    let ptr = *self.NamedValues.get(&prm.name).unwrap();
    let val = Function_getArg(f, argIdx) as Value*;
    if(is_struct(&prm.type)){
      self.copy(ptr, val, &prm.type);
    }else{
      CreateStore(self.ll.get().builder, val, ptr);
    }
    self.own.get().add_prm(prm, LLVMPtr::new(ptr));
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

  func getType(self, e: Expr*): Type{
    let rt = self.get_resolver().visit_cached(e);
    let res = rt.type.clone();
    return res;
  }

  func get_drop_proto(self, rt: RType*): FunctionInfo{
    let resolver = self.get_resolver();
    let decl = resolver.get_decl(rt).unwrap();
    let helper = DropHelper::new(resolver);
    let method = helper.get_drop_method(rt);
    if(method.is_generic){
      panic("generic {:?}", rt.type);
    }
    let protos = self.protos.get();
    let mangled = mangle(method);
    if(!protos.funcMap.contains(&mangled)){
      self.make_proto(method);
    }
    let proto = protos.get_func(method);
    return proto;
  }
  func drop_force(self, rt: RType*, ptr: LLVMPtr, line: i32, rhs: Rhs*){
    //An array or tuple value has no decl, so there is no drop function to
    //call for it: drop its drop-typed elements instead. Both shapes used to
    //panic here -- get_drop_proto below does get_decl(rt).unwrap(), which is
    //None for a decl-less type ("unwrap on None", option.x:26) -- whenever
    //an element was a drop type. Element count/size are compile-time
    //constants, so unroll; that keeps this straight-line (no new basic
    //blocks, no interaction with the control flow of the statement being
    //emitted).
    let helper = DropHelper::new(self.get_resolver());
    if let Type::Array(elem, size) = &rt.type{
      if(!helper.is_drop_type(elem.get())){
        return;
      }
      let elem_rt = self.get_resolver().visit_type(elem.get());
      let ll = self.ll.get();
      let arr_ty = self.mapType(&rt.type);
      let zero = ll.makeInt(0, 64);
      for(let i = 0;i < *size;++i){
        let ep = ll.gep_arr(arr_ty, ptr.ptr as Value*, zero, ll.makeInt(i as i64, 64));
        self.drop_force(&elem_rt, LLVMPtr::new(ep), line, rhs);
      }
      return;
    }
    if let Type::Tuple(tt) = &rt.type{
      let ll = self.ll.get();
      let tup_ty = self.mapType(&rt.type);
      for(let i = 0;i < tt.types.len();++i){
        let elem = tt.types.get(i);
        if(!helper.is_drop_type(elem)){
          continue;
        }
        let elem_rt = self.get_resolver().visit_type(elem);
        let ep = CreateStructGEP(ll.builder, tup_ty, ptr.ptr as Value*, i);
        self.drop_force(&elem_rt, LLVMPtr::new(ep), line, rhs);
      }
      return;
    }
    if let Type::Lambda(ltb) = &rt.type{
      if(ltb.get().captured.empty()){
        return;
      }
      //A capturing lambda owns its heap closure object. Phase A captures only
      //plain values, so freeing the object is the whole drop (phase B drops
      //the captured owners first); see doc/closures.txt. `ptr` is the place of
      //the value, so load the object pointer out of it.
      //Reuse a `free` that the unit already resolved (std/libc declares it),
      //otherwise declare it. Declaring it eagerly in init would take the name
      //first and push the library's own `free` to `free.1` (link error).
      let protos = self.protos.get();
      let ll = self.ll.get();
      let fk = String::new("free");
      if(protos.funcMap.get(&fk).is_none()){
        protos.funcMap.add(fk.clone(), make_free(ll));
      }
      let fproto = protos.funcMap.get(&fk).unwrap();
      let obj = ll.loadPtr(ptr.ptr as Value*);
      let args = [obj];
      CreateCall(ll.builder, fproto.val, args.ptr(), 1);
      return;
    }
    let proto = self.get_drop_proto(rt);
    let args = [ptr.ptr as Value*];
    let ll = self.ll.get();
    CreateCall(ll.builder, proto.val, args.ptr(), 1);
  }
}