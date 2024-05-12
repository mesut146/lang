import parser/resolver
import parser/ast
import parser/printer
import parser/utils
import parser/copier
import parser/bridge
import parser/compiler_helper
import parser/alloc_helper
import parser/debug_helper
import std/map
import std/io
import std/libc

struct Compiler{
  ctx: Context;
  config: Config;
  resolver: Option<Resolver*>;
  main_file: Option<String>;
  llvm: llvm_holder;
  compiled: List<String>;
  protos: Option<Protos>;
  NamedValues: Map<String, Value*>;
  allocMap: Map<i32, Value*>;
  curMethod: Option<Method*>;
  loops: List<BasicBlock*>;
  loopNext: List<BasicBlock*>;
}

struct llvm_holder{
  target_machine: TargetMachine*;
  target_triple: CStr;
  di: Option<DebugInfo>;
}

struct Config{
  verbose: bool;
  single_mode: bool;
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
  func get_func(self, nm: String*): Function*{
    return *self.funcMap.get_ptr(nm).unwrap();
  }
  func get_func(self, m: Method*): Function*{
    let id = mangle(m);
    return *self.funcMap.get_ptr(&id).unwrap();
  }
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
  noext.append("-bt.o");
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
  func initModule(self, path: CStr*){
    let name = getName(path.get());
    make_ctx();
    make_module(name.str().cstr().ptr(), self.target_machine, self.target_triple.ptr());
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
     config: Config{verbose: true, single_mode: true},
     resolver: Option<Resolver*>::None,
     main_file: Option<String>::new(),
     llvm: vm,
     compiled: List<String>::new(),
     protos: Option<Protos>::new(),
     NamedValues: Map<String, Value*>::new(),
     allocMap: Map<i32, Value*>::new(),
     curMethod: Option<Method*>::new(),
     loops: List<BasicBlock*>::new(),
     loopNext: List<BasicBlock*>::new()};
  }

  func get_resolver(self): Resolver*{
    return *self.resolver.get();
  }

  func unit(self): Unit*{
    return &self.get_resolver().unit;
  }

  func link_run(self, name0: str, args: str){
    let name_pre = format("./{}", name0);
    name0 = name_pre.str();
    let name: CStr = name0.cstr();
    if(exist(name0)){
      remove(name.ptr());
    }
    let cmd = "clang-16 ".str();
    cmd.append("-o ");
    cmd.append(name0);
    cmd.append(" ");
    Drop::drop(name_pre);
    for(let i = 0;i < self.compiled.len();++i){
      let file = self.compiled.get_ptr(i);
      cmd.append(file.str());
      cmd.append(" ");
    }
    self.compiled.clear();
    cmd.append(args);
    let cmd_s = cmd.cstr();
    if(system(cmd_s.ptr()) == 0){
      //run if linked
      if(system(name.ptr()) != 0){
        print("{}\n", cmd_s);
        panic("error while running {}", name);
      }
    }else{
      panic("link failed '{}'", cmd_s);
    }
  }

  func compile(self, path0: CStr): String{
    //print("compile {}\n", path0);
    let path = Path::new(path0.get_heap());
    let outFile: String = get_out_file(path0.get());
    let ext = path.ext();
    if (!ext.eq("x")) {
      panic("invalid extension {}", ext);
    }
    if(self.config.verbose){
      print("compiling {}\n", path0);
    }
    self.resolver = Option::new(self.ctx.create_resolver(&path.path));//Resolver*
    if (has_main(self.unit())) {
      self.main_file = Option::new(path0.get_heap());
      if (!self.config.single_mode) {//compile last
          print("skip main file\n");
          return outFile;
      }
    }
    self.get_resolver().resolve_all();
    // if(true){
    //   //r.unit.drop();
    //   return outFile;
    // }
    self.llvm.initModule(&path0);
    self.createProtos();
    //init_globals(this);
    
    let methods = getMethods(self.unit());
    for (let i = 0;i < methods.len();++i) {
      let m = *methods.get_ptr(i);
      self.genCode(m);
    }
    //generic methods from resolver
    for (let i=0;i<self.get_resolver().generated_methods.len();++i) {
        let m = self.get_resolver().generated_methods.get_ptr(i);
        self.genCode(m);
    }
    
    let name = getName(path0.get());
    let llvm_file = format("{}-bt.ll", trimExtenstion(name));
    let llvm_file_cstr = llvm_file.cstr();
    emit_llvm(llvm_file_cstr.ptr());
    if(self.config.verbose){
      print("writing {}\n", llvm_file_cstr);
    }
    self.compiled.add(outFile.clone());
    let outFile_cstr = CStr::new(outFile.clone());
    emit_object(outFile_cstr.ptr(), self.llvm.target_machine, self.llvm.target_triple.ptr());
    if(self.config.verbose){
      print("writing {}\n", outFile_cstr);
    }
    Drop::drop(outFile_cstr);
    Drop::drop(path0);
    self.cleanup();
    return outFile;
  }

  func cleanup(self){
    self.NamedValues.clear();
  }

  //make all struct decl & method decl used by this module
  func createProtos(self){
    self.protos = Option::new(Protos::new());
    let p = self.protos.get();
    let list = List<Decl*>::new();
    getTypes(self.unit(), &list);
    for (let i = 0;i < self.get_resolver().used_types.len();++i) {
      let decl = *self.get_resolver().used_types.get_ptr(i);
      if (decl.is_generic) continue;
      list.add(decl);
    }
    sort(&list, self.get_resolver());
    //first create just protos to fill later
    for(let i=0;i<list.len();++i){
      let decl = *list.get_ptr(i);
      let st = make_decl_proto(decl);
      p.classMap.add(decl.type.print(), st as llvm_Type*);
    }
    //fill with elems
    for(let i=0;i<list.len();++i){
      let decl = *list.get_ptr(i);
      self.make_decl(decl, p.get(decl) as StructType*);
    }
    //di proto
    for(let i=0;i<list.len();++i){
      let decl = *list.get_ptr(i);
      self.llvm.di.get().map_di_proto(decl, self);
    }
    //di fill
    for(let i=0;i<list.len();++i){
      let decl = *list.get_ptr(i);
      self.llvm.di.get().map_di_fill(decl, self);
    }
    
    //methods
    let methods = getMethods(self.unit());
    for (let i=0;i<methods.len();++i) {
      let m = methods.get(i);
      self.make_proto(m);
    }
    //generic methods from resolver
    for (let i = 0;i < self.get_resolver().generated_methods.len();++i) {
        let m = self.get_resolver().generated_methods.get_ptr(i);
        self.make_proto(m);
    }
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
    let id = mangle(m);
    let f = self.protos.get().get_func(&id);
    self.protos.get().cur = Option::new(f);
    let bb = create_bb2(f);
    self.NamedValues.clear();
    SetInsertPoint(bb);
    self.llvm.di.get().dbg_func(m, f, self);
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
    self.llvm.di.get().finalize();
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
    Value_setName(ptr, prm.name.clone().cstr().ptr());
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
    let argNo = 1;
    if (m.self.is_some()) {
      let prm = m.self.get();
      self.store_prm(prm, f, argIdx);
      self.llvm.di.get().dbg_prm(prm, argNo, self);
      ++argIdx;
      ++argNo;
    }
    for(let i=0;i<m.params.len();++i){
      let prm = m.params.get_ptr(i);
      self.store_prm(prm, f, argIdx);
      self.llvm.di.get().dbg_prm(prm, argNo, self);
      ++argIdx;
      ++argNo;
    }
  }
  
  func get_alloc(self, e: Expr*): Value*{
    let ptr = self.allocMap.get_ptr(&e.id);
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
    let rt = self.get_resolver().visit(e);
    return rt.type.clone();
  }
 
}

//stmt
impl Compiler{
  func visit(self, node: Stmt*){
    if let Stmt::Ret(e*)=(node){
      if(e.is_none()){
        if(is_main(self.curMethod.unwrap())){
          CreateRet(makeInt(0, 32));
        }else{
          CreateRetVoid();
        }
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
    else if let Stmt::If(is*)=(node){
      self.visit_if(is);
    }
    else if let Stmt::IfLet(is*)=(node){
      self.visit_iflet(is);
    }
    else if let Stmt::Block(b*)=(node){
      self.visit(b);
    }
    else if let Stmt::For(fs*)=(node){
      self.visit_for(fs);
    }
    else if let Stmt::While(cnd*, body*)=(node){
      self.visit_while(cnd, body);
    }
    else if(node is Stmt::Continue){
      CreateBr(*self.loops.last());
    }
    else if(node is Stmt::Break){
      CreateBr(*self.loopNext.last());
    }
    else{
      panic("visit {}", node);
    }
    return;
  }
  
  func visit_while(self, c: Expr*, body: Block*){
    let then = create_bb();
    let condbb = create_bb2(self.cur_func());
    let next = create_bb();
    CreateBr(condbb);
    SetInsertPoint(condbb);
    CreateCondBr(self.branch(c), then, next);
    self.set_and_insert(then);
    self.loops.add(condbb);
    self.loopNext.add(next);
    self.visit(body);
    self.loops.pop_back();
    self.loopNext.pop_back();
    CreateBr(condbb);
    self.set_and_insert(next);
  }

  func visit_iflet(self, node: IfLet*){
    let rt = self.get_resolver().visit(&node.ty);
    let decl = rt.targetDecl.unwrap();
    let rhs = self.get_obj_ptr(&node.rhs);
    let tag_ptr = self.gep2(rhs, get_tag_index(decl), self.mapType(&decl.type));
    let tag = CreateLoad(getInt(ENUM_TAG_BITS()), tag_ptr);
    let index = Resolver::findVariant(decl, node.ty.name());
    let cmp = CreateCmp(get_comp_op("==".cstr().ptr()), tag, makeInt(index, ENUM_TAG_BITS()));

    let then = create_bb2(self.cur_func());
    let next = create_bb();
    let elsebb = Option<BasicBlock*>::new();
    if(node.els.is_some()){
      elsebb = Option<BasicBlock*>::new(create_bb());
      CreateCondBr(self.branch(cmp), then, elsebb.unwrap());
    }else{
      CreateCondBr(self.branch(cmp), then, next);
    }
    SetInsertPoint(then);
    let variant = decl.get_variants().get_ptr(index);
    if(!variant.fields.empty()){
        //declare vars
        let params = &variant.fields;
        let data_index = get_data_index(decl);
        let dataPtr = self.gep2(rhs, data_index, self.mapType(&decl.type));
        let var_ty = self.get_variant_ty(decl, variant);
        for (let i = 0; i < params.size(); ++i) {
            //regular var decl
            let prm = params.get_ptr(i);
            let arg = node.args.get_ptr(i);
            let field_ptr = self.gep2(dataPtr, i, var_ty);
            let alloc_ptr = self.get_alloc(arg.id);
            self.NamedValues.add(arg.name.clone(), alloc_ptr);
            if (arg.is_ptr) {
                CreateStore(field_ptr, alloc_ptr);
            } else {
                if (prm.type.is_prim() || prm.type.is_pointer()) {
                    let field_val = CreateLoad(self.mapType(&prm.type), field_ptr);
                    CreateStore(field_val, alloc_ptr);
                } else {
                    self.copy(alloc_ptr, field_ptr, &prm.type);
                }
            }
        }
    }
    self.visit(node.then.get());
    if (!isReturnLast(node.then.get())) {
      CreateBr(next);
    }
    if (node.els.is_some()) {
        self.set_and_insert(elsebb.unwrap());
        self.visit(node.els.get().get());
        if (!isReturnLast(node.els.get().get())) {
            CreateBr(next);
        }
    }
    self.set_and_insert(next);
  }

  func visit_for(self, node: ForStmt*){
    if(node.v.is_some()){
      self.visit(node.v.get());
    }
    let f = self.cur_func();
    let then = create_bb();
    let condbb = create_bb2(f);
    let updatebb = create_bb2(f);
    let next = create_bb();

    CreateBr(condbb);
    SetInsertPoint(condbb);
    if (node.e.is_some()) {
      CreateCondBr(self.branch(node.e.get()), then, next);
    } else {
      CreateBr(then);
    }
    self.set_and_insert(then);
    self.loops.add(updatebb);
    self.loopNext.add(next);
    self.visit(node.body.get());
    CreateBr(updatebb);
    SetInsertPoint(updatebb);
    for (let i=0;i<node.u.len();++i) {
      let u = node.u.get_ptr(i);
      self.visit(u);
    }
    self.loops.pop_back();
    self.loopNext.pop_back();
    CreateBr(condbb);
    self.set_and_insert(next);
  }

  func visit_if(self, node: IfStmt*){
    let cond = self.branch(&node.e);
    let then = create_bb2(self.cur_func());
    let elsebb = Option<BasicBlock*>::new();
    let next = create_bb();
    if(node.els.is_some()){
      elsebb = Option::new(create_bb());
      CreateCondBr(cond, then, elsebb.unwrap());
    }else{
      CreateCondBr(cond, then, next);
    }
    SetInsertPoint(then);
    self.visit(node.then.get());
    if(!isReturnLast(node.then.get())){
      CreateBr(next);
    }
    if(node.els.is_some()){
      self.set_and_insert(elsebb.unwrap());
      self.visit(node.els.get().get());
      if(!isReturnLast(node.els.get().get())){
        CreateBr(next);
      }
    }
    self.set_and_insert(next);
  }
  func visit_assert(self, expr: Expr*){
    let m = self.curMethod.unwrap();
    let msg = format("{}:{} in {}\nassertion {} failed\n", m.path, expr.line, m.name, expr).cstr();
    let ptr = CreateGlobalStringPtr(msg.ptr());
    Drop::drop(msg);
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
      if(doesAlloc(&f.rhs, self.get_resolver())){
        //self allocated
        self.visit(&f.rhs);
        continue;
      }
      let type = &self.get_resolver().visit(f).type;
      if(is_struct(type)){
        let val = self.visit(&f.rhs);
        if(Value_isPointerTy(val)){
          self.copy(ptr, val, type);
        }else{
          CreateStore(val, ptr);
        }
      }else if(type.is_pointer()){
        let val = self.visit(&f.rhs);
        CreateStore(val, ptr);
      } else{
        let val = self.cast(&f.rhs, type);
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
    type = &self.get_resolver().visit(type).type;
    if(type.is_pointer()){
      let val = self.get_obj_ptr(expr);
      CreateRet(val);
      return;
    }
    if(!is_struct(type)){
      let val = self.cast(expr, type);
      CreateRet(val);
      return;
    }
    let ptr = get_arg(self.protos.get().cur.unwrap(), 0) as Value*;
    let val = self.visit(expr);
    self.copy(ptr, val, type);
    CreateRetVoid();
  }
}

//----------------------------------------------------------
//expr------------------------------------------------------
impl Compiler{
  func visit(self, node: Expr*): Value*{
    self.llvm.di.get().loc(node.line, node.pos);
    if let Expr::Par(e*)=(node){
      return self.visit(e.get());
    }
    if let Expr::Obj(type*,args*)=(node){
      return self.visit_obj(node, type, args);
    }
    if let Expr::Lit(lit*)=(node){
      return self.visit_lit(node, lit);
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
        return self.visit_deref(node, e.get());
      }
      return self.visit_unary(op, e.get());
    }
    if let Expr::Call(mc*)=(node){
      return self.visit_call(node, mc);
    }
    if let Expr::ArrAccess(aa*)=(node){
      return self.visit_aa(node, aa);
    }
    if let Expr::Array(list*, sz*)=(node){
      return self.visit_array(node, list, sz);
    }
    if let Expr::Access(scope*, name*)=(node){
      return self.visit_access(node, scope.get(), name);
    }
    if let Expr::Type(type*)=(node){
      return self.simple_enum(node ,type);
    }
    if let Expr::Is(lhs*, rhs*)=(node){
      return self.visit_is(lhs.get(), rhs.get());
    }
    if let Expr::As(lhs*, rhs*)=(node){
      return self.visit_as(lhs.get(), rhs);
    }
    panic("expr {}", node);
  }

  func visit_as(self, lhs: Expr*, rhs: Type*): Value*{
    let lhs_type = self.getType(lhs);
    let rhs_type = &self.get_resolver().visit(rhs).type;
    //ptr to int
    if (lhs_type.is_pointer() && lhs_type.print().eq("u64")) {
      let val = self.get_obj_ptr(lhs);
        return CreatePtrToInt(val, self.mapType(rhs_type));
    }
    if (lhs_type.is_prim()) {
      return self.cast(lhs, rhs_type);
    }
    return self.get_obj_ptr(lhs);
  }

  func visit_is(self, lhs: Expr*, rhs: Expr*): Value*{
    let tag1 = self.getTag(lhs);
    let op = get_comp_op("==".ptr());
    if let Expr::Type(rhs_ty*)=(rhs){
      let decl = self.get_resolver().visit(rhs_ty).targetDecl.unwrap();
      let index = Resolver::findVariant(decl, rhs_ty.name());
      let tag2 = makeInt(index, ENUM_TAG_BITS());
      return CreateCmp(op, tag1, tag2);
    }
    let tag2 = self.getTag(rhs);
    return CreateCmp(op, tag1, tag2);
  }

  func simple_enum(self, node: Expr*, type: Type*): Value*{
    let smp = type.as_simple();
    let decl = self.get_resolver().visit(smp.scope.get()).targetDecl.unwrap();
    let index = Resolver::findVariant(decl, &smp.name);
    let ptr = self.get_alloc(node);
    let decl_ty = self.mapType(&decl.type);
    let tag_ptr = self.gep2(ptr, get_tag_index(decl),decl_ty);
    CreateStore(makeInt(index, ENUM_TAG_BITS()), tag_ptr);
    return ptr;
  }

  func visit_access(self, node: Expr*, scope: Expr*, name: String*): Value*{
    let scope_ptr = self.get_obj_ptr(scope);
    let rt = self.get_resolver().visit(scope);
    let decl = rt.targetDecl.unwrap();
    let pair = self.get_resolver().findField(node, name, decl, &decl.type);
    let index = pair.b;
    if(decl is Decl::Enum){
      //enum base
      //todo more depth
      //scope_ptr = self.gep2(scope_ptr, 1, self.mapType(&decl.type));
    }
    if (pair.a.base.is_some()) ++index;
    let sd_ty = self.mapType(&pair.a.type);
    return self.gep2(scope_ptr, index, sd_ty);
  }

  func visit_array(self, node: Expr*, list: List<Expr>*, sz: Option<i32>*): Value*{
    let ptr = self.get_alloc(node);
    let arrt = self.getType(node);
    let elem_type = self.getType(list.get_ptr(0));
    let arr_ty = self.mapType(&arrt);
    if(sz.is_none()){
      for(let i = 0;i<list.len();++i){
        let e = list.get_ptr(i);
        let elem_target = gep_arr(arr_ty, ptr, 0, i);
        let et = self.getType(e);
        self.setField(e, &et, elem_target);
      }
      return ptr;
    }
    let elem = list.get_ptr(0);
    let elem_ptr = Option<Value*>::new();
    let elem_ty = self.mapType(&elem_type);
    if (doesAlloc(elem, self.get_resolver())) {
        elem_ptr = Option::new(self.visit(elem));
    }
    let bb = GetInsertBlock();
    let cur = gep_arr(arr_ty, ptr, 0, 0);
    let end = gep_arr(arr_ty, ptr, 0, *sz.get());
    //create cons and memcpy
    let condbb = create_bb();
    let setbb = create_bb();
    let nextbb = create_bb();
    CreateBr(condbb);
    self.set_and_insert(condbb);
    let phi_ty = getPointerTo(elem_ty);
    let phi = CreatePHI(phi_ty, 2);
    phi_addIncoming(phi, cur, bb);
    let ne = CreateCmp(get_comp_op("!=".ptr()), phi as Value*, end);
    CreateCondBr(ne, setbb, nextbb);
    self.set_and_insert(setbb);
    if (elem_ptr.is_some()) {
        self.copy(phi as Value*, elem_ptr.unwrap(), &elem_type);
    } else {
        self.setField(elem, &elem_type, phi as Value*);
    }
    let step = gep_ptr(elem_ty, phi as Value*, makeInt(1, 64));
    phi_addIncoming(phi, step, setbb);
    CreateBr(condbb);
    self.set_and_insert(nextbb);
    return ptr;
  }

  func visit_aa(self, expr: Expr*, node: ArrAccess*): Value*{
    let type = self.getType(node.arr.get());
    if(node.idx2.is_some()){
      return self.visit_slice(expr, node);
    }
    let i64t = Type::new("i64");
    let ty = type.unwrap_ptr();
    let src = self.get_obj_ptr(node.arr.get());
    if(ty.is_array()){
        //regular array access
        let i1 = makeInt(0, 64);
        let i2 = self.cast(node.idx.get(), &i64t);
        return gep_arr(self.mapType(ty), src, i1, i2);
    }
    
    //slice access
    let elem = ty.elem();
    let elemty = self.mapType(elem);
    //read array ptr
    let sliceType = self.protos.get().std("slice") as llvm_Type*;
    let arr = self.gep2(src, SLICE_PTR_INDEX(), sliceType);
    arr = CreateLoad(getPtr(), arr);
    let index = self.cast(node.idx.get(), &i64t);
    return gep_ptr(elemty, arr, index);
  }
  func visit_slice(self,expr: Expr*, node: ArrAccess*): Value*{
    let ptr = self.get_alloc(expr);
    let arr = self.visit(node.arr.get());
    let arr_ty = self.getType(node.arr.get());
    if(arr_ty.is_slice()){
      arr = CreateLoad(getPtr(), arr);
    }
    let elem_ty = arr_ty.elem();
    let i32_ty = Type::new("i32");
    let val_start = self.cast(node.idx.get(), &i32_ty);

    let ptr_ty = self.mapType(elem_ty);
    //shift by start
    arr = gep_ptr(ptr_ty, arr, val_start);

    let sliceType = self.protos.get().std("slice");

    let trg_ptr = self.gep2(ptr, 0, sliceType as llvm_Type*);
    let trg_len = self.gep2(ptr, 1, sliceType as llvm_Type*);
    //store ptr
    CreateStore(arr, trg_ptr);
    //set len
    let val_end = self.cast(node.idx2.get().get(), &i32_ty);
    let len = CreateSub(val_end, val_start);
    len = CreateSExt(len, getInt(SLICE_LEN_BITS()));
    CreateStore(len, trg_len);
    return ptr;
  }

  func visit_unary(self, op: String*, e: Expr*): Value*{
    let val = self.loadPrim(e);
    if(op.eq("+")) return val;
    if(op.eq("!")){
      val = CreateTrunc(val, getInt(1));
      val = CreateXor(val, getTrue());
      return CreateZExt(val, getInt(8));
    }
    let bits = getPrimitiveSizeInBits2(val);
    if(op.eq("-")){
      return CreateNSWSub(makeInt(0, bits), val);
    }
    if(op.eq("++")){
      let v = self.visit(e);//var without load
      let res = CreateNSWAdd(val, makeInt(1, bits));
      CreateStore(res, v);
      return res;
    }
    if(op.eq("--")){
      let v = self.visit(e);//var without load
      let res = CreateNSWSub(val, makeInt(1, bits));
      CreateStore(res, v);
      return res;
    }
    if(op.eq("~")){
      return CreateXor(val, makeInt(-1, bits));
    }
    panic("unary {}", op);
  }

  func visit_call(self, expr: Expr*, mc: Call*): Value*{
    if(Resolver::std_size(mc)){
      if(!mc.args.empty()){
        let ty = self.getType(mc.args.get_ptr(0));
        let sz = self.getSize(&ty);
        return makeInt(sz, 32);
      }else{
        let ty = mc.type_args.get_ptr(0);
        let sz = self.getSize(ty);
        return makeInt(sz, 32);
      }
    }    
    if(Resolver::std_is_ptr(mc)){
      let ty = mc.type_args.get_ptr(0);
      if(ty.is_pointer()){
        return getTrue();
      }
      return getFalse();
    }
    if(Resolver::is_printf(mc)){
      self.call_printf(mc);
      return getVoidTy() as Value*;
    }
    if(mc.name.eq("print") && mc.scope.is_none()){
      return self.visit_print(mc);
    }
    if(mc.name.eq("panic") && mc.scope.is_none()){
      self.visit_panic(expr, mc);
      return getTrue();
    }
    if(mc.name.eq("malloc") && mc.scope.is_none()){
      let i64_ty = Type::new("i64");
      let size = self.cast(mc.args.get_ptr(0), &i64_ty);
      if (!mc.type_args.empty()) {
          let typeSize = self.getSize(mc.type_args.get_ptr(0)) / 8;
          size = CreateNSWMul(size, makeInt(typeSize, 64));
      }
      let proto = self.protos.get().libc("malloc");
      let args = make_args();
      args_push(args, size);
      return CreateCall(proto, args);
    }
    if(Resolver::is_ptr_get(mc)){
      let elem_type = self.getType(expr).unwrap_ptr();
      let src = self.get_obj_ptr(mc.args.get_ptr(0));
      let idx = self.loadPrim(mc.args.get_ptr(1));
      return gep_ptr(self.mapType(elem_type), src, idx);
    }
    if(self.get_resolver().is_array_get_len(mc)){
      let arr_type = self.getType(mc.scope.get().get()).unwrap_ptr();
      if let Type::Array(elem*, sz)=(arr_type){
        return makeInt(sz, 64);
      }
      panic("");
    }
    //arr.ptr()
    if(self.get_resolver().is_array_get_ptr(mc)){
      return self.get_obj_ptr(mc.scope.get().get());
    }
    if(self.get_resolver().is_slice_get_len(mc)){
      let sl = self.get_obj_ptr(mc.scope.get().get());
      let sliceType=self.protos.get().std("slice") as llvm_Type*;
      let len_ptr = self.gep2(sl, SLICE_LEN_INDEX(), sliceType);
      return CreateLoad(getInt(SLICE_LEN_BITS()), len_ptr);
    }
    if(self.get_resolver().is_slice_get_ptr(mc)){
      let sl = self.get_obj_ptr(mc.scope.get().get());
      let sliceType=self.protos.get().std("slice") as llvm_Type*;
      let ptr = self.gep2(sl, SLICE_PTR_INDEX(), sliceType);
      return CreateLoad(getPtr(), ptr);
    }
    return self.visit_call2(expr, mc);
  }

  func visit_panic(self, node: Expr*, mc: Call*){
    let msg = String::new("panic");
    msg.append("\n");
    msg.append(self.curMethod.unwrap().path.str());
    msg.append(":");
    msg.append(i32::print(node.line).str());
    msg.append("\n in function ");
    msg.append(printMethod(self.curMethod.unwrap()).str());
    msg.append("\n");
    
    self.call_printf(msg.str());
    //printf
    let pr_mc = Call::new("print".str());
    //let id = node as Node*;
    //pr_mc.args.add(Expr::Lit{.*id, Literal{LitKind::STR, msg, Option<Type>::new()}});
    self.visit_print(mc);
    self.call_printf("\n");
    //exit
    self.call_exit(1);
  }

  func visit_call2(self, expr: Expr*, mc: Call*): Value*{
    let rt = self.get_resolver().visit(expr);
    if(rt.method.is_none()){
      panic("mc {}", expr);
    }
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
    let argIdx = 0;
    if(target.self.is_some()){
      let rval = RvalueHelper::need_alloc(mc, target, self.get_resolver());
      let scp_val = self.get_obj_ptr(*rval.scope.get());
      if(rval.rvalue){
        let rv_ptr = self.get_alloc(*rval.scope.get());
        CreateStore(scp_val, rv_ptr);
        args_push(args, rv_ptr);
      }else{
        args_push(args, scp_val);
      }
      if(mc.is_static){
        ++argIdx;
      }
      //++paramIdx;
    }
    for(;argIdx < mc.args.len();++argIdx){
      let arg = mc.args.get_ptr(argIdx);
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
        let pt = &self.get_resolver().visit(&prm.type).type;
        args_push(args, self.cast(arg, pt));
      }
      ++paramIdx;
    }
    let res = CreateCall(proto, args);
    if(ptr.is_some()) return ptr.unwrap();
    return res;
  }

  func visit_print(self, mc: Call*): Value*{
    let args = make_args();
    for(let i = 0;i < mc.args.len();++i){
      let arg: Expr* = mc.args.get_ptr(i);
      let lit = is_str_lit(arg);
      if(lit.is_some()){
        let val: str = lit.unwrap().str();
        val = val.substr(1, val.len() - 1);//trim quotes
        let ptr = CreateGlobalStringPtr(CStr::from_slice(val).ptr());
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
      }else if(arg_type.is_prim()){
        let val = self.loadPrim(arg);
        //val = CreateLoad(self.mapType(&arg_type), val);
        args_push(args, val);
      }else{
        panic("print {}", arg_type);
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

  func call_printf(self, mc: Call*){
    let args = make_args();
    for(let i = 0;i < mc.args.len();++i){
      let arg: Expr* = mc.args.get_ptr(i);
      let lit = is_str_lit(arg);
      if(lit.is_some()){
        let val: str = lit.unwrap().str();
        let ptr = CreateGlobalStringPtr(CStr::from_slice(val).ptr());
        args_push(args, ptr);
        continue;
      }
      let arg_type = self.getType(arg);
      if(arg_type.eq("i8*") || arg_type.eq("u8*")){
        let val = self.get_obj_ptr(arg);
        args_push(args, val);
        continue;
      }
      if(arg_type.is_prim()){
        let val = self.loadPrim(arg);
        args_push(args, val);
      }else{
        panic("compiler err printf arg {}", arg_type);
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
  }
  
  func call_printf(self, s: str){
    let args = make_args();
    let val = CreateGlobalStringPtr(s.cstr().ptr());
    args_push(args, val);
    let printf_proto = self.protos.get().libc("printf");
    let res = CreateCall(printf_proto, args);
    //flush
    let fflush_proto = self.protos.get().libc("fflush");
    let args2 = make_args();
    let stdout_ptr = self.protos.get().stdout_ptr;
    args_push(args2, CreateLoad(getPtr(), stdout_ptr));
    CreateCall(fflush_proto, args2);
  }

  func visit_deref(self, node: Expr*, e: Expr*): Value*{
    let type = self.getType(node);
    let val = self.get_obj_ptr(e);
    if (type.is_prim() || type.is_pointer()) {
        return self.load(val, &type);
    }
    return val;
  }

  func visit_infix(self, op: String*, l: Expr*, r: Expr*): Value*{
    let type = &self.get_resolver().visit(l).type;
    if(is_comp(op.str())){
      //todo remove redundant cast
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateCmp(get_comp_op(op.clone().cstr().ptr()), lv, rv);
    }
    if(op.eq("&&") || op.eq("||")){
      return self.andOr(op, l, r).a;
    }
    if(op.eq("=")){
      return self.visit_assign(l, r);
    }
    if(op.eq("+")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateNSWAdd(lv, rv);
    }
    if(op.eq("-")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateNSWSub(lv, rv);
    }
    if(op.eq("*")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateNSWMul(lv, rv);
    }
    if(op.eq("/")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateSDiv(lv, rv);
    }
    if(op.eq("%")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateSRem(lv, rv);
    }
    if(op.eq("&")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateAnd(lv, rv);
    }
    if(op.eq("|")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateOr(lv, rv);
    }
    if(op.eq("^")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateXor(lv, rv);
    }
    if(op.eq("<<")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateShl(lv, rv);
    }
    if(op.eq(">>")){
      let lv = self.cast(l, type);
      let rv = self.cast(r, type);
      return CreateAShr(lv, rv);
    }
    if(op.eq("+=")){
      let lv = self.visit(l);
      let lval = self.loadPrim(l);
      let rval = self.cast(r, type);
      let tmp = CreateNSWAdd(lval, rval);
      CreateStore(tmp, lv);
      return lv;
    }
    if(op.eq("-=")){
      let lv = self.visit(l);
      let lval = self.loadPrim(l);
      let rval = self.cast(r, type);
      let tmp = CreateNSWSub(lval, rval);
      CreateStore(tmp, lv);
      return lv;
    }
    if(op.eq("/=")){
      let lv = self.visit(l);
      let lval = self.loadPrim(l);
      let rval = self.cast(r, type);
      let tmp = CreateSDiv(lval, rval);
      CreateStore(tmp, lv);
      return lv;
    }
    panic("infix '{}'\n", op);
  }

  func is_logic(expr: Expr*): bool{
    if let Expr::Par(e*)=(expr){
      return is_logic(e.get());
    }
    if let Expr::Infix(op*, l*, r*)=(expr){
      if(op.eq("&&") || op.eq("||")){
        return true;
      }
    }
    return false;
  }

  func andOr(self, op: String*, l: Expr*, r: Expr*): Pair<Value*, BasicBlock*>{
    let isand = true;
    if(op.eq("||")) isand = false;

    let lval = self.branch(l);//must be eval first
    let bb = GetInsertBlock();
    let then = create_bb2(self.cur_func());
    let next = create_bb();
    if (isand) {
      CreateCondBr(lval, then, next);
    } else {
      CreateCondBr(lval, next, then);
    }
    SetInsertPoint(then);
    let rv = Option<Value*>::new();
    if(is_logic(r)){
      let r_inner = r;
      if let Expr::Par(e*)=(r){
        r_inner = e.get();
      }
      if let Expr::Infix(op2*,l2*,r2*)=(r_inner){
        let pair = self.andOr(op2, l2.get(), r2.get());
        then = pair.b;
        rv = Option::new(pair.a);
      }else{
        panic("");
      }
    }else{
      rv = Option::new(self.loadPrim(r));
    }
    let rbit = CreateZExt(rv.unwrap(), getInt(8));
    CreateBr(next);
    self.set_and_insert(next);
    let phi = CreatePHI(getInt(8), 2);
    let i8val = 0;
    if(!isand){
      i8val = 1;
    }
    phi_addIncoming(phi, makeInt(i8val, 8), bb);
    phi_addIncoming(phi, rbit, then);
    return Pair::new(CreateZExt(phi as Value*, getInt(8)), next);
  }

  func visit_assign(self, l: Expr*, r: Expr*): Value*{
    if(l is Expr::Infix) panic("assign lhs");
    //let lhs = Option<Value*>::new();
    let type = self.getType(l);
    if let Expr::Unary(op*,l2*)=(l){
      if(op.eq("*")){
        let lhs = self.get_obj_ptr(l2.get());
        //let rt = self.get_resolver().visit(l);
        self.setField(r, &type, lhs);
        return lhs;
      }
    }
    let lhs = self.visit(l);
    self.setField(r, &type, lhs);
    return lhs;
  }
  
  func visit_lit(self, expr: Expr*, node: Literal*): Value*{
    if(node.kind is LitKind::INT){
        let bits = 32;
        if (node.suffix.is_some()) {
            bits = self.getSize(node.suffix.get()) as i32;
        }
        let s = node.val.clone().replace("_", "");
        if (node.val.str().starts_with("0x")){
          let val = i64::parse_hex(s.str());
          return makeInt(val, bits);
        }
        let val = i64::parse(s.str());
        let res = makeInt(val, bits);
        return res;
    }
    if(node.val.eq("true")) return getTrue();
    if(node.val.eq("false")) return getFalse();
    if(node.kind is LitKind::STR){
      let trg_ptr = self.get_alloc(expr);
      let trimmed = node.val.substr(1, (node.val.len() as i32) - 1);//quote
      let src = CreateGlobalStringPtr(trimmed.cstr().ptr());
      let stringType = self.protos.get().std("str") as llvm_Type*;
      let sliceType = self.protos.get().std("slice") as llvm_Type*;
      let slice_ptr = self.gep2(trg_ptr, 0, stringType);
      let data_target = self.gep2(slice_ptr, SLICE_PTR_INDEX(), sliceType);
      let len_target = self.gep2(slice_ptr, SLICE_LEN_INDEX(), sliceType);
      //set ptr
      CreateStore(src, data_target);
      //set len
      let len = makeInt(trimmed.len(), SLICE_LEN_BITS());
      CreateStore(len, len_target);
      return trg_ptr;
    }
    if(node.kind is LitKind::CHAR){
      let trimmed = node.val.get(1);
      return makeInt(trimmed, 32);
    }
    panic("lit {}", node.val);
  }

  func set_fields(self, ptr: Value*, decl: Decl*,ty: llvm_Type*, args: List<Entry>*, fields: List<FieldDecl>*){
    let field_idx = 0;
    for(let i=0;i<args.len();++i){
      let arg = args.get_ptr(i);
      if(arg.isBase){
        continue;
      }
      let prm_idx = 0;
      if(arg.name.is_some()){
        prm_idx = Resolver::fieldIndex(fields, arg.name.get().str(), &decl.type);
      }else{
        prm_idx = field_idx;
        ++field_idx;
      }
      let fd = fields.get_ptr(prm_idx);
      if(decl.base.is_some() && decl is Decl::Struct) ++prm_idx;
      //Value_dump(ptr);
      //Type_dump(ty);
      let field_target_ptr = self.gep2(ptr, prm_idx, ty);
      self.setField(&arg.expr, &fd.type, field_target_ptr);
    }
  }
  
  func visit_obj(self, node: Expr*, type: Type*, args: List<Entry>*): Value*{
      let ptr = self.get_alloc(node);
      let rt = self.get_resolver().visit(node);
      let ty = self.mapType(&rt.type);
      let decl = rt.targetDecl.unwrap();
      for(let i=0;i<args.len();++i){
        let arg = args.get_ptr(i);
        if(!arg.isBase) continue;
        let base_ptr = self.gep2(ptr, 0, ty);
        let val_ptr = self.visit(&arg.expr);
        self.copy(base_ptr, val_ptr, &rt.type);
      }
      if let Decl::Struct(fields*)=(decl){
        let field_idx = 0;
        for(let i=0;i<args.len();++i){
          let arg = args.get_ptr(i);
          if(arg.isBase){
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
        let variant_index = Resolver::findVariant(decl, type.name());
        let variant = decl.get_variants().get_ptr(variant_index);
        //set tag
        let tag_ptr = self.gep2(ptr, get_tag_index(decl), ty);
        let tag_val = makeInt(variant_index, ENUM_TAG_BITS());
        CreateStore(tag_val, tag_ptr);
        //set data
        let data_ptr = self.gep2(ptr, get_data_index(decl), ty);
        let var_ty = self.get_variant_ty(decl, variant);
        self.set_fields(data_ptr, decl, var_ty, args, &variant.fields);
      }
      return ptr;
  }
}