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
impl Drop for Protos{
  func drop(*self){
    self.classMap.drop();
    self.funcMap.drop();
    self.libc.drop();
    self.std.drop();
  }
}

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
    name.drop();
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
      mangled.drop();
      return self.compiler.make_proto(m).unwrap();
      //panic("no proto for {}, {}", mangled, demangle(mangled.str()));
    }
    mangled.drop();
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
 
    self.ll = Option::new(LLVMInfo::new(name));
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
    
    if(self.config.opt_level.is_some()){
      self.ll.get().optimize_module_newpm(self.config.opt_level.get());
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
      let init = ptr::null<Value>();
      let name_c = gl_info.name.clone().cstr();
      let glob = make_global(ll.module, ty, init as Constant*, GlobalValue_ext(), name_c.ptr());
      self.globals.add(gl_info.name.clone(), glob as Value*);
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
        name_c.drop();
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
      name_c.drop();
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
      rt.drop();
    }
    if(self.config.debug){
      replaceGlobalVariables(ll.ctx, self.di.get().cu, globs.ptr(), globs.len() as i32);
    }
    make_global_ctors(proto, ll);
    CreateRetVoid(ll.builder);
    self.own.reset();
    self.di.get().finalize();
    verifyFunction(proto);
    globs.drop();
    method.drop();
    globals.drop();
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
        rhs_str.drop();
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
    self.ctx.prog.compile_begin(m);
    self.curMethod = Option<Method*>::new(m);
    self.own.drop();
    self.own = Option::new(Own::new(self, m));
    let proto = self.protos.get().get_func(m);
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
        //setField(blk_val.unwrap(), &m.type, );
        self.visit_ret(blk_val.unwrap());
        self.own.get().do_move(m.body.get().return_expr.get());
      }
    }
    self.di.get().finalize();
    verifyFunction(proto.val);
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
    let ptr = CreateAlloca(self.ll.get().builder, ty);
    Value_setName(ptr, name_c.ptr());
    self.NamedValues.add(prm.name.clone(), ptr);
    name_c.drop();
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
    rt.drop();
    return res;
  }

  func get_drop_proto(self, rt: RType*): FunctionInfo{
    let resolver = self.get_resolver();
    let decl = resolver.get_decl(rt).unwrap();
    let helper = DropHelper{resolver};
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
    mangled.drop();
    return proto;
  }
  func drop_force(self, rt: RType*, ptr: LLVMPtr, line: i32, rhs: Rhs*){
    let proto = self.get_drop_proto(rt);
    let args = [ptr.ptr as Value*];
    let ll = self.ll.get();
    CreateCall(ll.builder, proto.val, args.ptr(), 1);
  }
}