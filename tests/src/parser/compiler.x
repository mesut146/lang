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
  allocMap: Map<i32, Value*>;
  curMethod: Option<Method*>;
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
    return Compiler{ctx: ctx, config: Config{verbose: true, single_mode: true},
     resolver: dummy_resolver(&ctx), main_file: Option<String>::new(),
     llvm: vm,
     compiled: List<String>::new(),
     protos: Option<Protos>::new(),
     NamedValues: Map<String, Value*>::new(),
     allocMap: Map<i32, Value*>::new(),
     curMethod: Option<Method*>::new()};
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
          print("skip main file\n");
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
      self.make_decl(decl, p.get(decl) as StructType*);
    }
    //todo di proto
    //methods
    let methods = getMethods(self.unit());
    for (let i=0;i<methods.len();++i) {
      let m = methods.get(i);
      self.make_proto(m);
    }
    //generic methods from resolver
    for (let i=0;i<self.resolver.generated_methods.len();++i) {
        let m = self.resolver.generated_methods.get_ptr(i);
        self.make_proto(m);
    }
    for (let i=0;i<self.resolver.used_methods.len();++i) {
        let m=self.resolver.used_methods.get(i);
        self.make_proto(m);
    }
  }

  func genCode(self, m: Method*){
    //print("gen %s\n", m.name.cstr());
    if(m.body.is_none()) return;
    if(m.is_generic) return;
    self.curMethod = Option<Method*>::new(m);
    let id = mangle(m);
    let f = self.protos.get().get_func(&id);
    self.protos.get().cur = Option::new(f);
    let bb = create_bb2(f);
    self.NamedValues.clear();
    SetInsertPoint(bb);
    self.makeLocals(m.body.get());
    self.allocParams(m);
    self.storeParams(m,f);
    //todo call globals

    self.visit(m.body.get());

    if(m.type.is_void()){
      if(is_main(m)){
        CreateRet(makeInt(0, 32));
      }else if(!isReturnLast(m.body.get())){
        CreateRetVoid();
      }
    }
    verifyFunction(f);
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
    Value_setName(ptr, prm.name.cstr());
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
  }

  func storeParams(self, m: Method*, f: Function*){
    let argIdx = 0;
    if(is_struct(&m.type)){
      ++argIdx;//sret
    }
    if (m.self.is_some()) {
      let prm = m.self.get();
      self.store_prm(prm, f, argIdx);
      ++argIdx;
    }
    for(let i=0;i<m.params.len();++i){
      let prm = m.params.get_ptr(i);
      self.store_prm(prm, f, argIdx);
      ++argIdx;
    }
  }
  
  func get_alloc(self, e: Expr*): Value*{
    let ptr = self.allocMap.get(e.id);
    return *ptr.unwrap();
  }
  
  func gep2(self, ptr: Value*, idx: i32, ty: llvm_Type*): Value*{
    return CreateStructGEP(ptr, idx, ty);
  }

  func cur_func(self): Function*{
    return self.protos.get().cur.unwrap();
  }

  func call_exit(self, code: i32){
    let args = make_args();
    args_push(args, makeInt(code, 32));
    let exit_proto = self.protos.get().libc("exit");
    CreateCall(exit_proto, args);
    CreateUnreachable();
  }

  func set_and_insert(self, bb: BasicBlock*){
    SetInsertPoint(bb);
    func_insert(self.cur_func(), bb);
  }

  func getType(self, e: Expr*): Type{
    return self.resolver.visit(e).type;
  }
 
}

//stmt
impl Compiler{
  func visit(self, node: Stmt*){
    if let Stmt::Ret(e*)=(node){
      if(e.is_none()){
        CreateRetVoid();
      }else{
        self.visit_ret(e.get());
      }
    }
    else if let Stmt::Var(ve*)=(node){
      self.visit(ve);
    }else if let Stmt::Assert(e*)=(node){
      self.visit_assert(e);
    }
    else if let Stmt::Expr(e*)=(node){
      self.visit(e);
    }
    else{
      panic("visit %s", node.print().cstr());
    }
    return;
  }
  func visit_assert(self, expr: Expr*){
    let msg = Fmt::format("assertion {} failed in {}:{}", expr.print().str(), self.curMethod.unwrap().name.str(), i32::print(expr.line).str());
    let ptr = CreateGlobalStringPtr(msg.cstr());
    let then = create_bb2(self.cur_func());
    let next = create_bb();
    let cond = self.branch(expr);
    CreateCondBr(cond, next, then);
    SetInsertPoint(then);
    //print error and exit
    let pr_args = make_args();
    args_push(pr_args, ptr);
    let printf_proto = self.protos.get().libc("printf");
    CreateCall(printf_proto, pr_args);
    self.call_exit(1);
    self.set_and_insert(next);
  }
  func visit(self, node: VarExpr*){
    for(let i=0;i<node.list.len();++i){
      let f = node.list.get_ptr(i);
      let ptr = *self.NamedValues.get_ptr(&f.name).unwrap();
      if(doesAlloc(&f.rhs, self.resolver)){
        //self allocated
        self.visit(&f.rhs);
        continue;
      }
      let type = self.resolver.visit(f).type;
      if(is_struct(&type)){
        let val = self.visit(&f.rhs);
        if(Value_isPointerTy(val)){
          self.copy(ptr, val, &type);
        }else{
          CreateStore(val, ptr);
        }
      }else{
        let val = self.cast(&f.rhs, &type);
        CreateStore(val, ptr);
      }
    }
  }
  func visit(self, node: Block*){
    for(let i=0;i<node.list.len();++i){
      let st = node.list.get_ptr(i);
      self.visit(st);
    }
  }
  func visit_ret(self, expr: Expr*){
    let type = &self.curMethod.unwrap().type;
    type = &self.resolver.visit(type).type;
    if(type.is_pointer()){
      panic("ptr ret");
    }
    else if(!is_struct(type)){
      let val = self.cast(expr, type);
      CreateRet(val);
    }else{
      let ptr = get_arg(self.protos.get().cur.unwrap(), 0);
      CreateRetVoid();
    }
    print("ret %s:%s\n", self.curMethod.unwrap().name.cstr(), type.print().cstr());
  }
}

//----------------------------------------------------------
//expr------------------------------------------------------
impl Compiler{
  func visit(self, node: Expr*): Value*{
    if let Expr::Array(list*,sz*)=(node){
      //let ptr = getalloc();

    }
    if let Expr::Obj(type*,args*)=(node){
      return self.visit_obj(node, type, args);
    }
    if let Expr::Lit(lit*)=(node){
      return self.visit_lit(lit);
    }
    if let Expr::Infix(op*, l*, r*)=(node){
      return self.visit_infix(op, l.get(), r.get());
    }
    if let Expr::Name(name*)=(node){
      return *self.NamedValues.get_ptr(name).unwrap();
    }
    if let Expr::Unary(op*, e*)=(node){
      if(op.eq("&")){
        return self.visit(e.get());
      }
      if(op.eq("*")){
        return self.visit_deref(e.get());
      }
    }
    if let Expr::Call(mc*)=(node){
      return self.visit_call(node, mc);
    }
    panic("expr %s", node.print().cstr());
  }

  func visit_call(self, expr: Expr*, mc: Call*): Value*{
    if(mc.name.eq("print") && mc.scope.is_none()){
      return self.visit_print(mc);
    }
    return self.visit_call2(expr, mc);
  }

  func visit_call2(self, expr: Expr*, mc: Call*): Value*{
    let rt = self.resolver.visit(expr);
    let type = &rt.type;
    let ptr = Option<Value*>::new();
    if(is_struct(type)){
      ptr = Option::new(self.get_alloc(expr));
    }
    let target = rt.method.unwrap();
    let proto = self.protos.get().get_func(target);
    let args = make_args();
    if(ptr.is_some()){
      args_push(args, ptr.unwrap());
    }
    let paramIdx = 0;
    if(target.self.is_some()){
      let scp = self.get_obj_ptr(mc.scope.get().get());
      args_push(args, scp);
      ++paramIdx;
    }
    for(let i=0;i<mc.args.len();++i){
      let arg = mc.args.get_ptr(i);
      let at = self.getType(arg);
      if (at.is_pointer()) {
        args_push(args, self.get_obj_ptr(arg));
      }
      else if (is_struct(&at)) {
        let de = is_deref(arg);
        if (de.is_some()) {
          args_push(args, self.get_obj_ptr(de.unwrap()));
        }
        else {
          args_push(args, self.visit(arg));
        }
      } else {
        let prm = target.params.get_ptr(paramIdx);
        let pt = self.resolver.visit(&prm.type).type;
        args_push(args, self.cast(arg, &pt));
      }
    }
    let res = CreateCall(proto, args);
    if(ptr.is_some()) return ptr.unwrap();
    return res;
  }

  func visit_print(self, mc: Call*): Value*{
    let args = make_args();
    for(let i=0;i<mc.args.len();++i){
      let arg = mc.args.get_ptr(i);
      let lit = is_str_lit(arg);
      if(lit.is_some()){
        let val = lit.unwrap().str();
        val = val.substr(1, val.len() - 1);//trim quotes
        let ptr = CreateGlobalStringPtr(val.cstr());
        args_push(args, ptr);
        continue;
      }
      let arg_type = self.getType(arg);
      if(arg_type.print().eq("i8*") || arg_type.print().eq("u8*")){
        let val = self.get_obj_ptr(arg);
        args_push(args, val);
      }
      else if(arg_type.is_str()){
        panic("print str");
      }else{
        panic("print ?");
      }
    }
    let printf_proto = self.protos.get().libc("printf");
    let res = CreateCall(printf_proto, args);
    //flush
    let fflush_proto = self.protos.get().libc("fflush");
    let args2 = make_args();
    let stdout_ptr = self.protos.get().stdout_ptr;
    args_push(args2, CreateLoad(getPtr(), stdout_ptr));
    CreateCall(fflush_proto, args2);
    return res;
  }

  func visit_deref(self, e: Expr*): Value*{
    let type = self.getType(e);
    let val = self.get_obj_ptr(e);
    if (type.is_prim() || type.is_pointer()) {
        return self.load(val, &type);
    }
    return val;
  }

  func visit_infix(self, op: String*, l: Expr*, r: Expr*): Value*{
    if(is_comp(op.str())){
      let type = self.resolver.visit(l).type;
      let lv = self.cast(l, &type);//todo remove
      let rv = self.cast(r, &type);
      return CreateCmp(get_comp_op(op.cstr()), lv, rv);
    }
    if(op.eq("=")){
      return self.visit_assign(l, r);
    }
    panic("infix '%s'\n", op.cstr());
  }

  func visit_assign(self, l: Expr*, r: Expr*): Value*{
    if(l is Expr::Infix) panic("assign lhs");
    let lhs = self.visit(l);
    let type = self.getType(l);
    self.setField(r, &type, lhs);
    return lhs;
  }
  
  func visit_lit(self, node: Literal*): Value*{
    if(node.kind is LitKind::INT){
        let bits = 32_i64;
        if (node.suffix.is_some()) {
            bits = self.getSize(node.suffix.get());
        }
        let base = 10;
        if (node.val.str().starts_with("0x")) base = 16;
        let val = i32::parse(&node.val);
        return makeInt(val, bits as i32);
    }
    panic("lit %s", node.val.cstr());
  }
  
  func visit_obj(self, node: Expr*, type: Type*, args: List<Entry>*): Value*{
      let ptr = self.get_alloc(node);
      let rt = self.resolver.visit(node);
      let ty = self.mapType(&rt.type);
      let decl = rt.targetDecl.unwrap();
      if let Decl::Struct(fields*)=(decl){
        let field_idx = 0;
        for(let i=0;i<args.len();++i){
          let arg = args.get_ptr(i);
          if(arg.isBase){
            let base_ptr = self.gep2(ptr, 0, ty);
            let val_ptr = self.visit(&arg.expr);
            self.copy(base_ptr, val_ptr, &rt.type);
            continue;
          }
          let prm_idx = 0;
          if(arg.name.is_some()){
            prm_idx = Resolver::fieldIndex(fields, arg.name.get().str(), &rt.type);
          }else{
            prm_idx = field_idx;
            ++field_idx;
          }
          let fd = fields.get_ptr(prm_idx);
          if(decl.base.is_some()) ++prm_idx;
          let field_target_ptr = self.gep2(ptr, prm_idx, ty);
          self.setField(&arg.expr, &fd.type, field_target_ptr);
        }
      }else{
      }
      return ptr;
  }
}