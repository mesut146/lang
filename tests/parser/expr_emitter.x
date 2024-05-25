import parser/compiler
import parser/stmt_emitter
import parser/resolver
import parser/ast
import parser/bridge
import parser/debug_helper
import parser/compiler_helper
import parser/utils
import parser/printer
import std/map

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
          return self.visit_ref(node, e.get());
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

    func visit_ref(self, node: Expr*, expr: Expr*): Value*{
      if (RvalueHelper::is_rvalue(expr)) {
        let allc = self.get_alloc(node);
        let val = self.loadPrim(expr);
        CreateStore(val, allc);
        return allc;
      }
      let inner = self.visit(expr);
      return inner;
    }

    func call_exit(self, code: i32){
        let args = make_args();
        args_push(args, makeInt(code, 32));
        let exit_proto = self.protos.get().libc("exit");
        CreateCall(exit_proto, args);
        CreateUnreachable();
      }
  
    func visit_as(self, lhs: Expr*, rhs: Type*): Value*{
      let lhs_type = self.getType(lhs);
      //ptr to int
      if (lhs_type.is_pointer() && rhs.print().eq("u64")) {
        let val = self.get_obj_ptr(lhs);
          return CreatePtrToInt(val, self.mapType(rhs));
      }
      if (lhs_type.is_prim()) {
        let rhs_type = &self.get_resolver().visit_type(rhs).type;
        return self.cast(lhs, rhs_type);
      }
      return self.get_obj_ptr(lhs);
    }
  
    func visit_is(self, lhs: Expr*, rhs: Expr*): Value*{
      let tag1 = self.getTag(lhs);
      let op = get_comp_op("==".ptr());
      if let Expr::Type(rhs_ty*)=(rhs){
        let decl = self.get_resolver().get_decl(rhs_ty).unwrap();
        let index = Resolver::findVariant(decl, rhs_ty.name());
        let tag2 = makeInt(index, ENUM_TAG_BITS());
        return CreateCmp(op, tag1, tag2);
      }
      let tag2 = self.getTag(rhs);
      return CreateCmp(op, tag1, tag2);
    }
  
    func simple_enum(self, node: Expr*, type: Type*): Value*{
      let smp = type.as_simple();
      let decl = self.get_resolver().get_decl(smp.scope.get()).unwrap();
      let index = Resolver::findVariant(decl, &smp.name);
      let ptr = self.get_alloc(node);
      let decl_ty = self.mapType(&decl.type);
      let tag_ptr = self.gep2(ptr, get_tag_index(decl),decl_ty);
      CreateStore(makeInt(index, ENUM_TAG_BITS()), tag_ptr);
      return ptr;
    }
  
    func visit_access(self, node: Expr*, scope: Expr*, name: String*): Value*{
      let scope_ptr = self.get_obj_ptr(scope);
      let scope_rt = self.getType(scope);
      let decl = self.get_resolver().get_decl(&scope_rt).unwrap();
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
      if(Resolver::is_drop_call(mc)){
        let argt = self.getType(mc.args.get_ptr(0));
        if(argt.is_pointer() || argt.is_prim()){
          return getVoidTy() as Value*;
        }
        let helper = DropHelper{self.get_resolver()};
        if(!helper.is_drop_type(&argt)){
          return getVoidTy() as Value*;
        }
      }
      if(Resolver::is_std_no_drop(mc)){
        let arg = mc.args.get_ptr(0);
        return getVoidTy() as Value*;
      }
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
      if(Resolver::is_print(mc)){
        let info = self.get_resolver().format_map.get_ptr(&expr.id).unwrap();
        self.visit_block(&info.block);
        return getVoidTy() as Value*;
      }
      if(Resolver::is_panic(mc)){
        let info = self.get_resolver().format_map.get_ptr(&expr.id).unwrap();
        self.visit_block(&info.block);
        self.call_exit(1);
        return getVoidTy() as Value*;
      }
      if(Resolver::is_format(mc)){
        let info = self.get_resolver().format_map.get_ptr(&expr.id).unwrap();
        self.visit_block(&info.block);
        return self.visit(info.unwrap_mc.get());
        /*let ptr = self.get_alloc(expr);
        return ptr;*/
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
      if(Resolver::is_ptr_deref(mc)){
        let arg_ptr = self.get_obj_ptr(mc.args.get_ptr(0));
        let type = self.getType(expr);
        if (!is_struct(&type)) {
            return CreateLoad(self.mapType(&type), arg_ptr);
        }
        return arg_ptr;
      }
      if(Resolver::is_ptr_get(mc)){
        let elem_type = self.getType(expr).unwrap_ptr();
        let src = self.get_obj_ptr(mc.args.get_ptr(0));
        let idx = self.loadPrim(mc.args.get_ptr(1));
        return gep_ptr(self.mapType(elem_type), src, idx);
      }
      if(Resolver::is_ptr_copy(mc)){
        //ptr::copy(src_ptr, src_idx, elem)
        let src_ptr = self.get_obj_ptr(mc.args.get_ptr(0));
        let i64_ty = Type::new("i64");
        let idx = self.cast(mc.args.get_ptr(1), &i64_ty);
        let val = self.visit(mc.args.get_ptr(2));
        let elem_type: Type = self.getType(mc.args.get_ptr(2));
        let trg_ptr = gep_ptr(self.mapType(&elem_type), src_ptr, idx);
        self.copy(trg_ptr, val, &elem_type);
        return getVoidTy() as Value*;
      }
      if(self.get_resolver().is_array_get_len(mc)){
        let arr_type = self.getType(mc.scope.get()).unwrap_ptr();
        if let Type::Array(elem*, sz)=(arr_type){
          return makeInt(sz, 64);
        }
        panic("");
      }
      if(self.get_resolver().is_array_get_ptr(mc)){
        //arr.ptr()
        return self.get_obj_ptr(mc.scope.get());
      }
      if(self.get_resolver().is_slice_get_len(mc)){
        //sl.len()
        let sl = self.get_obj_ptr(mc.scope.get());
        let sliceType=self.protos.get().std("slice") as llvm_Type*;
        let len_ptr = self.gep2(sl, SLICE_LEN_INDEX(), sliceType);
        return CreateLoad(getInt(SLICE_LEN_BITS()), len_ptr);
      }
      if(self.get_resolver().is_slice_get_ptr(mc)){
        //sl.ptr()
        let sl = self.get_obj_ptr(mc.scope.get());
        let sliceType=self.protos.get().std("slice") as llvm_Type*;
        let ptr = self.gep2(sl, SLICE_PTR_INDEX(), sliceType);
        return CreateLoad(getPtr(), ptr);
      }
      return self.visit_call2(expr, mc);
    }
  
    func visit_call2(self, expr: Expr*, mc: Call*): Value*{
      let rt = self.get_resolver().visit(expr);
      if(!rt.is_method()){
        panic("mc no method {} {}", expr, rt.desc);
      }
      //print("{}\n", expr);
      if(expr.print().eq("(self.len()).debug(&f_9)")){
        let aa = 10;
      }
      let type = &rt.type;
      let ptr = Option<Value*>::new();
      if(is_struct(type)){
        ptr = Option::new(self.get_alloc(expr));
      }
      let target = self.get_resolver().get_method(&rt).unwrap();
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
          let pt = &self.get_resolver().visit_type(&prm.type).type;
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
      if(node.kind is LitKind::BOOL){
        if(node.val.eq("true")) return getTrue();
        return getFalse();
      }
      if(node.kind is LitKind::STR){
        let trg_ptr = self.get_alloc(expr);
        let src = CreateGlobalStringPtr(node.val.clone().cstr().ptr());
        let stringType = self.protos.get().std("str") as llvm_Type*;
        let sliceType = self.protos.get().std("slice") as llvm_Type*;
        let slice_ptr = self.gep2(trg_ptr, 0, stringType);
        let data_target = self.gep2(slice_ptr, SLICE_PTR_INDEX(), sliceType);
        let len_target = self.gep2(slice_ptr, SLICE_LEN_INDEX(), sliceType);
        //set ptr
        CreateStore(src, data_target);
        //set len
        let len = makeInt(node.val.len(), SLICE_LEN_BITS());
        CreateStore(len, len_target);
        return trg_ptr;
      }
      if(node.kind is LitKind::CHAR){
        assert node.val.len() == 1;
        let trimmed = node.val.get(0);
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
        let decl = self.get_resolver().get_decl(&rt).unwrap();
        for(let i = 0;i < args.len();++i){
          let arg = args.get_ptr(i);
          if(!arg.isBase) continue;
          let base_ptr = self.gep2(ptr, 0, ty);
          let val_ptr = self.visit(&arg.expr);
          let base_rt = self.get_resolver().visit(&arg.expr);
          self.copy(base_ptr, val_ptr, &base_rt.type);
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
}//end impl