import parser/compiler
import parser/stmt_emitter
import parser/resolver
import parser/ast
import parser/bridge
import parser/debug_helper
import parser/compiler_helper
import parser/utils
import parser/printer
import parser/ownership
import parser/own_model
import parser/derive
import parser/drop_helper
import std/map
import std/stack

struct MatchInfo{
  type: Type;
  val: Value*;
  bb: BasicBlock*;
}

//expr------------------------------------------------------
impl Compiler{

    func visit(self, node: Expr*): Value*{
      let res = self.visit_expr(node);
      //self.own.get().add_obj(node);
      return res;
    }

    func visit_expr(self, node: Expr*): Value*{
      self.llvm.di.get().loc(node.line, node.pos);
      if let Expr::If(is*)=(node){
        let res = self.visit_if(is.get());
        if(res.is_none()){
          return ConstantPointerNull_get(getPointerTo(getVoidTy()));
        }
        return res.unwrap();
      }
      else if let Expr::IfLet(is*)=(node){
        let res = self.visit_iflet(node.line, is.get());
        if(res.is_none()){
          return ConstantPointerNull_get(getPointerTo(getVoidTy()));
        }
        return res.unwrap();
      }
      else if let Expr::Block(b*)=(node){
        let res = self.visit_block(b.get());
        if(res.is_none()){
          return ConstantPointerNull_get(getPointerTo(getVoidTy()));
        }
        return res.unwrap();
      }
      else if let Expr::Par(e*)=(node){
        return self.visit(e.get());
      }
      if let Expr::Obj(type*, args*)=(node){
        return self.visit_obj(node, type, args);
      }
      if let Expr::Lit(lit*)=(node){
        return self.visit_lit(node, lit);
      }
      if let Expr::Infix(op*, l*, r*)=(node){
        return self.visit_infix(node, op, l.get(), r.get());
      }
      if let Expr::Name(name*)=(node){
        return self.visit_name(node, name, true);
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
      if let Expr::MacroCall(mc*)=(node){
        return self.visit_macrocall(node, mc);
      }
      if let Expr::ArrAccess(aa*)=(node){
        return self.visit_array_access(node, aa);
      }
      if let Expr::Array(list*, sz*)=(node){
        return self.visit_array(node, list, sz);
      }
      if let Expr::Access(scope*, name*)=(node){
        return self.visit_access(node, scope.get(), name);
      }
      if let Expr::Type(type*)=(node){
          let r = self.get_resolver();
          let rt = r.visit(node);
          if(rt.type.is_fpointer() && rt.method_desc.is_some()){
              let target: Method* = r.get_method(&rt).unwrap();
              let proto = self.protos.get().get_func(target);
              rt.drop();
              return proto as Value*;
          }
          rt.drop();
          return self.simple_enum(node, type);
      }
      if let Expr::Is(lhs*, rhs*)=(node){
        return self.visit_is(lhs.get(), rhs.get());
      }
      if let Expr::As(lhs*, rhs*)=(node){
        return self.visit_as(lhs.get(), rhs);
      }
      if let Expr::Match(me*)=(node){
        let res = self.visit_match(node, me.get());
        if(res.is_none()){
          return ConstantPointerNull_get(getPointerTo(getVoidTy()));
        }
        return res.unwrap();
      }
      if let Expr::Lambda(le*)=(node){
          let r = self.get_resolver();
          let m = r.lambdas.get(&node.id).unwrap();
          let proto = self.protos.get().get_func(m);
          
          return proto as Value*;
      }
      panic("expr {:?}", node);
    }

    func get_variant_index_match(case: MatchCase*, decl: Decl*): i32{
      let idx = 0;
      let name: String* = case.lhs.get_type().name();
      for ev in decl.get_variants(){
        if(ev.name.eq(name)){
          return idx;
        }
        ++idx;
      }
      panic("idx {:?} {:?}", case.lhs.get_type(), decl.type);
    }

    func visit_match_rhs(self, rhs: MatchRhs*): Option<Value*>{
      match rhs{
        MatchRhs::EXPR(e*)=>{
          return Option<Value*>::new(self.visit(e));
        },
        MatchRhs::STMT(st*)=>{
          self.visit(st);
          return Option<Value*>::new();
        }
      }
    }

    func visit_match(self, expr: Expr*, node: Match*): Option<Value*>{
      let rhs_rt = self.get_resolver().visit(&node.expr);
      let decl = self.get_resolver().get_decl(&rhs_rt).unwrap();
      let rhs = self.get_obj_ptr(&node.expr);
      let tag_ptr = CreateStructGEP(rhs, get_tag_index(decl), self.mapType(&decl.type));
      let tag = CreateLoad(getInt(ENUM_TAG_BITS()), tag_ptr);

      let next_name = format("next_{}", expr.line).cstr();
      let nextbb = create_bb_named(next_name.ptr());
      let none_case = node.has_none();
      let def_name = format("def_{}", expr.line).cstr();
      let def_bb = create_bb_named(def_name.ptr());
      let sw = CreateSwitch(tag, def_bb, node.cases.len() as i32);
      let match_rt = self.get_resolver().visit(expr);
      let match_type = match_rt.unwrap();
      if(none_case.is_none()){
        self.set_and_insert(def_bb);
        CreateUnreachable();
      }
      //create bb's
      let res = Option<Value*>::new();
      let infos = List<MatchInfo>::new();
      let use_next = false;
      for case in &node.cases{
        if(case.lhs is MatchLhs::NONE){
          self.set_and_insert(def_bb);
          let rhs_val = self.visit_match_rhs(&none_case.unwrap().rhs);
          let exit = Exit::get_exit_type(&none_case.unwrap().rhs);
          if(!exit.is_jump()){
              CreateBr(nextbb);
              use_next = true;
              if(!match_type.is_void()){
                let rt2 = self.get_resolver().visit_match_rhs(&case.rhs);
                infos.add(MatchInfo{rt2.unwrap(), rhs_val.unwrap(), def_bb});
              }
          }
        }else if let MatchLhs::ENUM(type*, args*) = (&case.lhs){
          let name_c = format("{:?}__{}_{}", decl.type, type.name(), expr.line).cstr();
          let bb = create_bb_named(name_c.ptr());
          let var_index = get_variant_index_match(case, decl);
          SwitchInst_addCase(sw, makeInt(var_index, 64), bb);
          self.set_and_insert(bb);
          //alloc args
          let variant = decl.get_variants().get(var_index);
          let arg_idx = 0;
          for arg in args{
            self.alloc_enum_arg(arg, variant, arg_idx, decl, rhs);
            ++arg_idx;
          }
          self.own.get().add_scope(ScopeType::MATCH_CASE, &case.rhs);
          let rhs_val = self.visit_match_rhs(&case.rhs);
          self.own.get().end_scope(Compiler::get_end_line(&case.rhs));
          let rhs_end_bb = GetInsertBlock();
          let exit = Exit::get_exit_type(&case.rhs);
          if(!exit.is_jump()){
            if(!match_type.is_void()){
              let rt2 = self.get_resolver().visit_match_rhs(&case.rhs);
              let val = rhs_val.unwrap();
              if(!is_struct(&match_type)){
                  //fix
                  if(match_type.is_prim() && Value_isPointerTy(val)){
                      val = CreateLoad(self.mapType(&match_type), val);
                  }
                  val = self.cast2(val, &rt2.type, &match_type);
              }
              rhs_val.set(val);
              infos.add(MatchInfo{rt2.unwrap(), rhs_val.unwrap(), rhs_end_bb});
            }
            CreateBr(nextbb);
            use_next = true;
          }
          name_c.drop();
        }
      }
      if(use_next){
          self.set_and_insert(nextbb);
      }
      //handle ret value
      if(!infos.empty()){
        let phi_type = self.mapType(&match_type);
        if(is_struct(&match_type)){
          phi_type = getPointerTo(phi_type) as llvm_Type*;
        }
        let phi = CreatePHI(phi_type, infos.len() as i32);
        //print("phi ty=\n");
        //Type_dump(phi_type);
        for info in &infos{
          //print("val=\n");
          //Value_dump(info.val);
          phi_addIncoming(phi, info.val, info.bb);
        }
        res = Option::new(phi as Value*);
      }
      def_name.drop();
      next_name.drop();
      rhs_rt.drop();
      return res;
    }

    func alloc_enum_arg(self, arg: ArgBind*, variant: Variant*, arg_idx: i32, decl: Decl*, enum_ptr: Value*){
      let data_index = get_data_index(decl);
      let dataPtr = CreateStructGEP(enum_ptr, data_index, self.mapType(&decl.type));
      let var_ty = self.get_variant_ty(decl, variant);

      let field = variant.fields.get(arg_idx);
      let alloc_ptr = self.get_alloc(arg.id);
      self.NamedValues.add(arg.name.clone(), alloc_ptr);
      let gep_idx = arg_idx;
      if(decl.base.is_some()){
        ++gep_idx;
      }
      let field_ptr = CreateStructGEP(dataPtr, gep_idx, var_ty);
      if (arg.is_ptr) {
        CreateStore(field_ptr, alloc_ptr);
        let ty_ptr = field.type.clone().toPtr();
        self.llvm.di.get().dbg_var(&arg.name, &ty_ptr, arg.line, self);
        ty_ptr.drop();
      } else {
        //deref
        if (field.type.is_prim() || field.type.is_any_pointer()) {
            let field_val = CreateLoad(self.mapType(&field.type), field_ptr);
            CreateStore(field_val, alloc_ptr);
        } else {
            //DropHelper::new(self.get_resolver()).is_drop_type(&node.rhs), delete this after below works
            self.copy(alloc_ptr, field_ptr, &field.type);
            self.own.get().add_iflet_var(arg, field, alloc_ptr, &decl.type);
        }
        self.llvm.di.get().dbg_var(&arg.name, &field.type, arg.line, self);
      }      
    }

    func visit_name(self, node: Expr*, name: String*, check: bool): Value*{
      let rt = self.get_resolver().visit(node);
      if(rt.desc.kind is RtKind::Const){
        let cn = self.get_resolver().get_const(&rt);
        match &cn.rhs{
          Expr::Lit(lit*) => {
            match &lit.kind{
              LitKind::INT => {
                return self.visit_lit(&cn.rhs, lit);
              },
              _ => {
                panic("todo const lit rhs {:?}", cn.rhs);
              }
            }
          },
          _ => {
            panic("todo const rhs {:?}", cn.rhs);
          }
        }
      }
      if(rt.type.is_fpointer()){
        if(rt.method_desc.is_some()){
          let target: Method* = self.get_resolver().get_method(&rt).unwrap();
          let proto = self.protos.get().get_func(target);
          rt.drop();
          return proto as Value*;
        }
      }
      if(self.globals.contains(name)){
        return *self.globals.get(name).unwrap();
      }
      let res = self.NamedValues.get(name);
      if(res.is_none()){
        self.get_resolver().err(node, format("internal err, no named value"));
      }
      if(check){
        self.own.get().check(node);
      }
      return *res.unwrap();
    }

    func visit_ref(self, node: Expr*, expr: Expr*): Value*{
      if (RvalueHelper::is_rvalue(expr)) {
        let alloc_ptr = self.get_alloc(node);
        //let val = self.loadPrim(expr);
        //CreateStore(val, alloc_ptr);
        let expr_type = self.get_resolver().getType(expr);
        self.setField(expr, &expr_type, alloc_ptr);
        self.own.get().add_obj(node, alloc_ptr, &expr_type);
        expr_type.drop();
        return alloc_ptr;
      }
      let inner = self.visit(expr);
      return inner;
    }
  
    func visit_as(self, lhs: Expr*, rhs: Type*): Value*{
      let lhs_rt = self.get_resolver().visit(lhs);
      //ptr to int
      if (lhs_rt.type.is_any_pointer() && rhs.eq("u64")) {
        let val = self.get_obj_ptr(lhs);
        lhs_rt.drop();
        return CreatePtrToInt(val, self.mapType(rhs));
      }
      let rhs_rt = self.get_resolver().visit_type(rhs);
      if (lhs_rt.type.is_prim()) {
        let res = self.cast(lhs, &rhs_rt.type);
        lhs_rt.drop();
        rhs_rt.drop();
        return res;
      }
      //enum to base, skip tag
      let val = self.get_obj_ptr(lhs);
      if(lhs_rt.is_decl()){
        let decl = self.get_resolver().get_decl(&lhs_rt).unwrap();
        if(decl.is_enum() && rhs_rt.is_decl()){
          val = CreateStructGEP(val, get_data_index(decl), self.mapType(&decl.type));
        }
      }
      lhs_rt.drop();
      rhs_rt.drop();
      return val;
    }
  
    func visit_is(self, lhs: Expr*, rhs: Expr*): Value*{
      let tag1 = self.getTag(lhs);
      let op = get_comp_op("==".ptr());
      if let Expr::Type(rhs_ty*)=(rhs){
        let decl = self.get_resolver().get_decl(rhs_ty).unwrap();
        let index = Resolver::findVariant(decl, rhs_ty.name());
        let tag2 = makeInt(index, ENUM_TAG_BITS()) as Value*;
        return CreateCmp(op, tag1, tag2);
      }
      let tag2 = self.getTag(rhs);
      return CreateCmp(op, tag1, tag2);
    }

    func simple_enum(self, node: Expr*, type: Type*): Value*{
      let ptr = self.get_alloc(node);
      return self.simple_enum(type, ptr);
    }
  
    func simple_enum(self, type: Type*, ptr: Value*): Value*{
      let smp = type.as_simple();
      let decl = self.get_resolver().get_decl(smp.scope.get()).unwrap();
      let index = Resolver::findVariant(decl, &smp.name);
      let decl_ty = self.mapType(&decl.type);
      let tag_ptr = CreateStructGEP(ptr, get_tag_index(decl), decl_ty);
      CreateStore(makeInt(index, ENUM_TAG_BITS()) as Value*, tag_ptr);
      return ptr;
    }
  
    func visit_access(self, node: Expr*, scope: Expr*, name: String*): Value*{
      let scope_ptr = self.get_obj_ptr(scope);
      let scope_rt = self.get_resolver().visit(scope);
      let decl = self.get_resolver().get_decl(&scope_rt).unwrap();
      if(decl.is_enum()){
        //base field, skip tag
        let ty = self.mapType(&decl.type);
        scope_ptr = CreateStructGEP(scope_ptr, get_data_index(decl), ty);
      }
      let pair = self.get_resolver().findField(node, name, decl, &decl.type);
      let index = pair.b;
      if (pair.a.base.is_some()) ++index;
      let sd_ty = self.mapType(&pair.a.type);
      scope_rt.drop();
      return CreateStructGEP(scope_ptr, index, sd_ty);
    }
  
    func visit_array(self, node: Expr*, list: List<Expr>*, sz: Option<i32>*): Value*{
      let ptr = self.get_alloc(node);
      return self.visit_array(node, list, sz, ptr);
    }
    func visit_array(self, node: Expr*, list: List<Expr>*, sz: Option<i32>*, ptr: Value*): Value*{
      let arrt = self.getType(node);
      self.own.get().add_obj(node, ptr, &arrt);
      let arr_ty = self.mapType(&arrt);
      arrt.drop();
      if(sz.is_none()){
        for(let i = 0;i < list.len();++i){
          let e = list.get(i);
          let elem_target = gep_arr(arr_ty, ptr, 0, i);
          let et = self.getType(e);
          self.setField(e, &et, elem_target);
          et.drop();
        }
        return ptr;
      }
      //repeated
      let elem = list.get(0);
      let elem_ptr = Option<Value*>::new();
      let elem_type = self.getType(list.get(0));
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
      let phi_ty = getPointerTo(elem_ty) as llvm_Type*;
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
      let step = gep_ptr(elem_ty, phi as Value*, makeInt(1, 64) as Value*);
      phi_addIncoming(phi, step, setbb);
      CreateBr(condbb);
      self.set_and_insert(nextbb);
      elem_type.drop();
      return ptr;
    }
  
    func visit_array_access(self, expr: Expr*, node: ArrAccess*): Value*{
      if(node.idx2.is_some()){
        return self.visit_slice(expr, node);
      }
      let i64t = Type::new("i64");
      let type = self.getType(node.arr.get());
      let ty = type.deref_ptr();
      let src = self.get_obj_ptr(node.arr.get());
      if(ty.is_array()){
        //regular array access
        let i1 = makeInt(0, 64) as Value*;
        let i2 = self.cast(node.idx.get(), &i64t);
        let res = gep_arr(self.mapType(ty), src, i1, i2);
        type.drop();
        i64t.drop();
        return res;
      }
      
      //slice access
      let elem = ty.elem();
      let elemty = self.mapType(elem);
      //read array ptr
      let sliceType = self.protos.get().std("slice") as llvm_Type*;
      let arr = CreateStructGEP(src, SLICE_PTR_INDEX(), sliceType);
      arr = CreateLoad(getPtr(), arr);
      let index = self.cast(node.idx.get(), &i64t);
      i64t.drop();
      type.drop();
      return gep_ptr(elemty, arr, index);
    }

    func visit_slice(self, expr: Expr*, node: ArrAccess*): Value*{
      let ptr = self.get_alloc(expr);
      return self.visit_slice(expr, node, ptr);
    }

    func visit_slice(self,expr: Expr*, node: ArrAccess*, ptr: Value*): Value*{
      let arr = self.visit(node.arr.get());
      let arr_ty = self.getType(node.arr.get());
      if(arr_ty.is_slice()){
        arr = CreateLoad(getPtr(), arr);
      }else if(arr_ty.is_pointer()){
        arr = CreateLoad(getPtr(), arr);
      }
      let elem_ty = arr_ty.elem();
      let i32_ty = Type::new("i32");
      let val_start = self.cast(node.idx.get(), &i32_ty);
      let ptr_ty = self.mapType(elem_ty);
      //shift by start
      arr = gep_ptr(ptr_ty, arr, val_start);
  
      let sliceType = self.protos.get().std("slice");
  
      let trg_ptr = CreateStructGEP(ptr, 0, sliceType as llvm_Type*);
      let trg_len = CreateStructGEP(ptr, 1, sliceType as llvm_Type*);
      //store ptr
      CreateStore(arr, trg_ptr);
      //set len
      let val_end = self.cast(node.idx2.get(), &i32_ty);
      let len = CreateSub(val_end, val_start);
      len = CreateSExt(len, getInt(SLICE_LEN_BITS()));
      CreateStore(len, trg_len);
      arr_ty.drop();
      i32_ty.drop();
      return ptr;
    }

    func makeFloat_one(type: Type*): Value*{
      if(type.eq("f32")){
        return makeFloat(1.0) as Value*;
      }
      return makeDouble(1.0) as Value*;
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
      let type = self.getType(e);
      if(op.eq("-")){
        if(type.is_float()){
          type.drop();
          return CreateFNeg(val);
        }
        type.drop();
        return CreateNSWSub(makeInt(0, bits) as Value*, val);
      }
      if(op.eq("++")){
        let var_ptr = self.visit(e);//var without load
        if(type.is_float()){
          let res = CreateFAdd(val, makeFloat_one(&type));
          CreateStore(res, var_ptr);
          return res;
        }
        if(type.is_unsigned()){
          let res = CreateAdd(val, makeInt(1, bits) as Value*);
          CreateStore(res, var_ptr);
          return res;
        }
        let res = CreateNSWAdd(val, makeInt(1, bits) as Value*);
        CreateStore(res, var_ptr);
        return res;
      }
      if(op.eq("--")){
        let var_ptr = self.visit(e);//var without load
        if(type.is_float()){
          let res = CreateFSub(val, makeFloat_one(&type));
          CreateStore(res, var_ptr);
          return res;
        }
        let res = CreateNSWSub(val, makeInt(1, bits) as Value*);
        CreateStore(res, var_ptr);
        return res;
      }
      if(op.eq("~")){
        return CreateXor(val, makeInt(-1, bits) as Value*);
      }
      panic("unary {}", op);
    }

    func is_drop_call2(mc: Call*): bool{
      return mc.name.eq("drop") && mc.scope.is_some() && mc.args.empty();
    }

    func visit_macrocall(self, expr: Expr*, mc: MacroCall*): Value*{
        let resolver = self.get_resolver();
        if(Resolver::is_call(mc, "ptr", "deref")){
          let arg_ptr = self.get_obj_ptr(mc.args.get(0));
          let type = self.getType(expr);
          if (!is_struct(&type)) {
              let res = CreateLoad(self.mapType(&type), arg_ptr);
              type.drop();
              return res;
          }
          type.drop();
          return arg_ptr;
        }
        if(Resolver::is_call(mc, "ptr", "get")){
          let elem_type = self.getType(expr);
          let src = self.get_obj_ptr(mc.args.get(0));
          let idx = self.loadPrim(mc.args.get(1));
          let res = gep_ptr(self.mapType(elem_type.deref_ptr()), src, idx);
          elem_type.drop();
          return res;
        }
        if(Resolver::is_call(mc, "ptr", "copy")){
          //ptr::copy(src_ptr, src_idx, elem)
          let src_ptr = self.get_obj_ptr(mc.args.get(0));
          let i64_ty = Type::new("i64");
          let idx = self.cast(mc.args.get(1), &i64_ty);
          i64_ty.drop();
          let val = self.visit(mc.args.get(2));
          let elem_type: Type = self.getType(mc.args.get(2));
          let trg_ptr = gep_ptr(self.mapType(&elem_type), src_ptr, idx);
          self.copy(trg_ptr, val, &elem_type);
          elem_type.drop();
          return getVoidTy() as Value*;
        }
        if(Resolver::is_call(mc, "std", "unreachable")){
          CreateUnreachable();
          return getVoidTy() as Value*;
        }
        if(Resolver::is_call(mc, "std", "internal_block")){
          let arg = mc.args.get(0).print();
          let id = i32::parse(arg.str()).unwrap();
          let blk: Block* = *resolver.block_map.get(&id).unwrap();
          self.visit_block(blk);
          arg.drop();
          return getVoidTy() as Value*;
        }
        if(Resolver::is_call(mc, "std", "typeof")){
          let arg = mc.args.get(0);
          let ty = self.getType(arg);
          let str = ty.print();
          let ptr = self.get_alloc(expr);
          let res = self.str_lit(str.str(), ptr);
          str.drop();
          ty.drop();
          return res;
        }
        if(Resolver::is_call(mc, "std", "no_drop")){
          let arg = mc.args.get(0);
          self.own.get().do_move(arg);
          return getVoidTy() as Value*;
        }
        let info = resolver.format_map.get(&expr.id);
        if(info.is_none()){
          resolver.err(expr, "internal err no macro");
        }
        let res = self.visit_block(&info.unwrap().block);
        if(res.is_some()) return res.unwrap();
        return getVoidTy() as Value*;
    }

    func visit_call(self, expr: Expr*, mc: Call*): Value*{
      let resolver = self.get_resolver();
      let env = std::getenv("ignore_drop");
      //todo dont remove this until own is stable
      if(is_drop_call2(mc) && env.is_some()){
        let list = env.unwrap().split(",");
        //let cur_name: str = Path::name(self.unit().path.str());
        let cur_name: str = Path::name(self.curMethod.unwrap().path.str()); 
        if(list.contains(&cur_name)){
          //let arg = mc.scope.get();
          //self.own.get().do_move(arg);
          list.drop();
          return getVoidTy() as Value*;
        }
        list.drop();
      }
      if(Resolver::is_call(mc, "std", "no_drop")){
        let arg = mc.args.get(0);
        self.own.get().do_move(arg);
        return getVoidTy() as Value*;
      }
      //////////////////////////////////////
      if(Resolver::is_call(mc, "ptr", "deref")){
        let arg_ptr = self.get_obj_ptr(mc.args.get(0));
        let type = self.getType(expr);
        if (!is_struct(&type)) {
            let res = CreateLoad(self.mapType(&type), arg_ptr);
            type.drop();
            return res;
        }
        type.drop();
        return arg_ptr;
      }
      if(Resolver::is_call(mc, "ptr", "get")){
        let elem_type = self.getType(expr);
        let src = self.get_obj_ptr(mc.args.get(0));
        let idx = self.loadPrim(mc.args.get(1));
        let res = gep_ptr(self.mapType(elem_type.deref_ptr()), src, idx);
        elem_type.drop();
        return res;
      }
      if(Resolver::is_call(mc, "ptr", "copy")){
        //ptr::copy(src_ptr, src_idx, elem)
        let src_ptr = self.get_obj_ptr(mc.args.get(0));
        let i64_ty = Type::new("i64");
        let idx = self.cast(mc.args.get(1), &i64_ty);
        i64_ty.drop();
        let val = self.visit(mc.args.get(2));
        let elem_type: Type = self.getType(mc.args.get(2));
        let trg_ptr = gep_ptr(self.mapType(&elem_type), src_ptr, idx);
        self.copy(trg_ptr, val, &elem_type);
        elem_type.drop();
        return getVoidTy() as Value*;
      }
      if(Resolver::is_call(mc, "std", "unreachable")){
        CreateUnreachable();
        return getVoidTy() as Value*;
      }
      if(Resolver::is_call(mc, "std", "internal_block")){
        let arg = mc.args.get(0).print();
        let id = i32::parse(arg.str()).unwrap();
        let blk: Block* = *resolver.block_map.get(&id).unwrap();
        self.visit_block(blk);
        arg.drop();
        return getVoidTy() as Value*;
      }
      if(Resolver::is_call(mc, "std", "typeof")){
        let arg = mc.args.get(0);
        let ty = self.getType(arg);
        let str = ty.print();
        let ptr = self.get_alloc(expr);
        let res = self.str_lit(str.str(), ptr);
        str.drop();
        ty.drop();
        return res;
      }
      if(Resolver::is_call(mc, "std", "no_drop")){
        let arg = mc.args.get(0);
        self.own.get().do_move(arg);
        return getVoidTy() as Value*;
      }
      /// /////////////////////////////
      let mac = resolver.format_map.get(&expr.id);
      if(mac.is_some()){
        let res = self.visit_block(&mac.unwrap().block);
        if(res.is_some()){
          return res.unwrap();
        }
        return getVoidTy() as Value*;
      }
      if(Resolver::is_call(mc, "std", "debug") || Resolver::is_call(mc, "std", "debug2")){
        let info = resolver.format_map.get(&expr.id).unwrap();
        self.visit_block(&info.block);
        return getVoidTy() as Value*;
      }
      if(Resolver::is_call(mc, "std", "print_type")){
        let info = resolver.format_map.get(&expr.id).unwrap();
        return self.visit_block(&info.block).unwrap();
      }
      if(Resolver::is_drop_call(mc)){
        //print("drop_call {} line: {}\n", expr, expr.line);
        let argt = self.getType(mc.args.get(0));
        if(argt.is_any_pointer() || argt.is_prim()){
          argt.drop();
          return getVoidTy() as Value*;
        }
        let helper = DropHelper{resolver};
        if(!helper.is_drop_type(&argt)){
          argt.drop();
          return getVoidTy() as Value*;
        }
        argt.drop();
      }

      if(Resolver::is_call(mc, "std", "size")){
        if(!mc.args.empty()){
          let ty = self.getType(mc.args.get(0));
          let sz = self.getSize(&ty) / 8;
          ty.drop();
          return makeInt(sz, 32) as Value*;
        }else{
          let ty = mc.type_args.get(0);
          let sz = self.getSize(ty) / 8;
          return makeInt(sz, 32) as Value*;
        }
      }    
      if(Resolver::is_call(mc, "std", "is_ptr")){
        let ty = mc.type_args.get(0);
        if(ty.is_pointer()){
          return getTrue();
        }
        return getFalse();
      }
      if(Resolver::is_printf(mc)){
        self.call_printf(mc);
        return getVoidTy() as Value*;
      }
      if(Resolver::is_sprintf(mc)){
        return self.call_sprintf(mc);
      }
      if(Resolver::is_print(mc)){
        let info = resolver.format_map.get(&expr.id).unwrap();
        self.visit_block(&info.block);
        return getVoidTy() as Value*;
      }
      if(Resolver::is_panic(mc)){
        let info = resolver.format_map.get(&expr.id).unwrap();
        self.visit_block(&info.block);
        return getVoidTy() as Value*;
      }
      if(Resolver::is_format(mc)){
        let info = resolver.format_map.get(&expr.id).unwrap();
        let res = self.visit_block(&info.block);
        self.own.get().do_move(info.block.return_expr.get());
        return res.unwrap();
      }
      if(Resolver::is_assert(mc)){
        let info = resolver.format_map.get(&expr.id).unwrap();
        self.visit_block(&info.block);
        return getVoidTy() as Value*;
      }
      if(mc.name.eq("malloc") && mc.scope.is_none()){
        let i64_ty = Type::new("i64");
        let size = self.cast(mc.args.get(0), &i64_ty);
        i64_ty.drop();
        if (!mc.type_args.empty()) {
            let typeSize = self.getSize(mc.type_args.get(0)) / 8;
            size = CreateNSWMul(size, makeInt(typeSize, 64) as Value*);
        }
        let proto = self.protos.get().libc("malloc");
        let args = vector_Value_new();
        vector_Value_push(args, size);
        let res = CreateCall(proto, args);
        vector_Value_delete(args);
        return res;
      }
      if(Resolver::is_call(mc, "ptr", "null")){
        let ty = self.mapType(mc.type_args.get(0));
        return ConstantPointerNull_get(getPointerTo(ty));
      }
      if(resolver.is_array_get_len(mc)){
        let arr_type = self.getType(mc.scope.get());
        let arr_type2 = arr_type.deref_ptr();
        if let Type::Array(elem*, sz)=(arr_type2){
          arr_type.drop();
          return makeInt(sz, 64) as Value*;
        }
        arr_type.drop();
        panic("");
      }
      if(resolver.is_array_get_ptr(mc)){
        //arr.ptr()
        return self.get_obj_ptr(mc.scope.get());
      }
      if(resolver.is_slice_get_len(mc)){
        //sl.len()
        let sl = self.get_obj_ptr(mc.scope.get());
        let sliceType=self.protos.get().std("slice") as llvm_Type*;
        let len_ptr = CreateStructGEP(sl, SLICE_LEN_INDEX(), sliceType);
        return CreateLoad(getInt(SLICE_LEN_BITS()), len_ptr);
      }
      if(resolver.is_slice_get_ptr(mc)){
        //sl.ptr()
        let sl = self.get_obj_ptr(mc.scope.get());
        let sliceType=self.protos.get().std("slice") as llvm_Type*;
        let ptr = CreateStructGEP(sl, SLICE_PTR_INDEX(), sliceType);
        return CreateLoad(getPtr(), ptr);
      }
      return self.visit_call2(expr, mc);
    }
    func visit_call2(self, expr: Expr*, mc: Call*): Value*{
      let resolver = self.get_resolver();
      let rt = resolver.visit(expr);
      if(rt.fp_info.is_some()){
          let ft = rt.fp_info.get();
          let val = self.visit_name(expr, &mc.name, false);
          val = CreateLoad(getPtr(), val);
          let proto = self.make_proto(ft);
          let args = vector_Value_new();
          let paramIdx = 0;
          for arg in &mc.args{
            let at = resolver.getType(arg);
            if (at.is_any_pointer()) {
              vector_Value_push(args, self.get_obj_ptr(arg));
            }
            else if (is_struct(&at)) {
              let de = is_deref(arg);
              if (de.is_some()) {
                vector_Value_push(args, self.get_obj_ptr(de.unwrap()));
              }
              else {
                vector_Value_push(args, self.visit(arg));
              }
            } else {
                let pt0 = ft.params.get(paramIdx);
                let pt = resolver.visit_type(pt0).unwrap();
                vector_Value_push(args, self.cast(arg, &pt));
                pt.drop();
            }
            ++paramIdx;
            at.drop();
          }
          //vector_Value_push(args, size);
          let res = CreateCall_ft(proto, val, args);
          vector_Value_delete(args);
          rt.drop();
          return res as Value*;
      }
      if(rt.lambda_call.is_some()){
          let val = self.visit_name(expr, &mc.name, false);
          val = CreateLoad(getPtr(), val);
          let ft0 = Option<LambdaType*>::none();
          if let Type::Lambda(bx*)=(&rt.lambda_call.get().type){
              ft0.set(bx.get());
          }else{
              panic("impossible");
              //Option<LambdaType>::none().get()
          }
          let ft = ft0.unwrap();
          let proto = self.make_proto(ft);
          let args = vector_Value_new();
          let paramIdx = 0;
          for arg in &mc.args{
            let at = resolver.getType(arg);
            if (at.is_any_pointer()) {
              vector_Value_push(args, self.get_obj_ptr(arg));
            }
            else if (is_struct(&at)) {
              let de = is_deref(arg);
              if (de.is_some()) {
                vector_Value_push(args, self.get_obj_ptr(de.unwrap()));
              }
              else {
                vector_Value_push(args, self.visit(arg));
              }
            } else {
                let pt0 = ft.params.get(paramIdx);
                let pt = resolver.visit_type(pt0).unwrap();
                vector_Value_push(args, self.cast(arg, &pt));
                pt.drop();
            }
            ++paramIdx;
            at.drop();
          }
          //vector_Value_push(args, size);
          let res = CreateCall_ft(proto, val, args);
          vector_Value_delete(args);
          rt.drop();
          return res as Value*;
          //resolver.err(expr, "lambda");
      }
      if(!rt.is_method()){
        resolver.err(expr, format("mc no method {:?}", expr));
      }
      //print("{}\n", expr);
      let ptr_ret = Option<Value*>::new();
      if(is_struct(&rt.type)){
        ptr_ret = Option::new(self.get_alloc(expr));
      }
      return self.visit_call2(expr, mc, ptr_ret, rt);
    }
  
    func visit_call2(self, expr: Expr*, mc: Call*, ptr_ret: Option<Value*>, rt: RType): Value*{
      if(is_struct(&rt.type)){
        self.own.get().add_obj(expr, ptr_ret.unwrap(), &rt.type);
      }
      let target: Method* = self.get_resolver().get_method(&rt).unwrap();
      self.cache.inc.depends_func(self.get_resolver(), target);
      rt.drop();
      let proto = self.protos.get().get_func(target);
      let args = vector_Value_new();
      if(ptr_ret.is_some()){
        vector_Value_push(args, ptr_ret.unwrap());
      }
      let paramIdx = 0;
      let argIdx = 0;
      if(target.self.is_some()){
        let rval = RvalueHelper::need_alloc(mc, target, self.get_resolver());
        let scp_val = self.get_obj_ptr(*rval.scope.get());
        if(rval.rvalue){
          let rv_ptr = self.get_alloc(*rval.scope.get());
          CreateStore(scp_val, rv_ptr);
          vector_Value_push(args, rv_ptr);
        }else{
          vector_Value_push(args, scp_val);
        }
        rval.drop();
        if(mc.is_static){
          ++argIdx;
          self.own.get().do_move(mc.args.get(0));
        }else if(target.self.get().is_deref){
          self.own.get().do_move(mc.scope.get());
        }
        //++paramIdx;
      }
      for(;argIdx < mc.args.len();++argIdx){
        let arg: Expr* = mc.args.get(argIdx);
        let at = self.getType(arg);
        let lit: Option<String*> = is_str_lit(arg);
        if(target.is_vararg && lit.is_some()){
          let val = self.get_global_string(lit.unwrap().clone());
          vector_Value_push(args, val);
        }
        else if (at.is_any_pointer()) {
          vector_Value_push(args, self.get_obj_ptr(arg));
        }
        else if (is_struct(&at)) {
          let de = is_deref(arg);
          if (de.is_some()) {
            vector_Value_push(args, self.get_obj_ptr(de.unwrap()));
          }
          else {
            vector_Value_push(args, self.visit(arg));
          }
        } else {
          if(target.is_vararg && paramIdx >= target.params.len()){
            vector_Value_push(args, self.loadPrim(arg));
          }else{
            let prm = target.params.get(paramIdx);
            let pt = self.get_resolver().getType(&prm.type);
            vector_Value_push(args, self.cast(arg, &pt));
            pt.drop();
          }
        }
        at.drop();
        self.own.get().do_move(arg);
        ++paramIdx;
      }
      if(Resolver::is_exit(mc)){
        self.print_frame();
      }
      let res = CreateCall(proto, args);
      vector_Value_delete(args);
      if(Resolver::is_exit(mc)){
        CreateUnreachable();
      }
      if(ptr_ret.is_some()) return ptr_ret.unwrap();
      return res;
    }
  
    func visit_print(self, mc: Call*): Value*{
      let args = vector_Value_new();
      for(let i = 0;i < mc.args.len();++i){
        let arg: Expr* = mc.args.get(i);
        let lit = is_str_lit(arg);
        if(lit.is_some()){
          let val: String = lit.unwrap().clone();
          let ptr = self.get_global_string(val);
          vector_Value_push(args, ptr);
          continue;
        }
        let arg_type = self.getType(arg);
        if(arg_type.eq("i8*") || arg_type.eq("u8*")){
          let val = self.get_obj_ptr(arg);
          vector_Value_push(args, val);
        }
        else if(arg_type.is_str()){
          panic("print str");
        }else if(arg_type.is_prim()){
          let val = self.loadPrim(arg);
          //val = CreateLoad(self.mapType(&arg_type), val);
          vector_Value_push(args, val);
        }else{
          panic("print {:?}", arg_type);
        }
        arg_type.drop();
      }
      let printf_proto = self.protos.get().libc("printf");
      let res = CreateCall(printf_proto, args);
      vector_Value_delete(args);
      //flush
      let fflush_proto = self.protos.get().libc("fflush");
      let args2 = vector_Value_new();
      let stdout_ptr = self.protos.get().stdout_ptr;
      vector_Value_push(args2, CreateLoad(getPtr(), stdout_ptr));
      CreateCall(fflush_proto, args2);
      vector_Value_delete(args2);
      return res;
    }
  
    func call_printf(self, mc: Call*){
      let args = vector_Value_new();
      for(let i = 0;i < mc.args.len();++i){
        let arg: Expr* = mc.args.get(i);
        let lit = is_str_lit(arg);
        if(lit.is_some()){
          let val: String = lit.unwrap().clone();
          let ptr = self.get_global_string(val);
          vector_Value_push(args, ptr);
          continue;
        }
        let arg_type = self.getType(arg);
        if(arg_type.eq("i8*") || arg_type.eq("u8*")){
          let val = self.get_obj_ptr(arg);
          vector_Value_push(args, val);
          arg_type.drop();
          continue;
        }
        if(arg_type.is_prim()){
          let val = self.loadPrim(arg);
          if(arg_type.eq("f32")){
            val = CreateFPExt(val, getDoubleTy());
          }
          vector_Value_push(args, val);
        }else if(arg_type.is_any_pointer()){
          let val = self.get_obj_ptr(arg);
          vector_Value_push(args, val);
          arg_type.drop();
          continue;
        }else{
          panic("compiler err printf arg {:?}", arg_type);
        }
        arg_type.drop();
      }
      let printf_proto = self.protos.get().libc("printf");
      let res = CreateCall(printf_proto, args);
      vector_Value_delete(args);
      //flush
      let fflush_proto = self.protos.get().libc("fflush");
      let args2 = vector_Value_new();
      let stdout_ptr = self.protos.get().stdout_ptr;
      vector_Value_push(args2, CreateLoad(getPtr(), stdout_ptr));
      CreateCall(fflush_proto, args2);
      vector_Value_delete(args2);
    }

    func call_sprintf(self, mc: Call*): Value*{
      let args = vector_Value_new();
      for(let i = 0;i < mc.args.len();++i){
        let arg: Expr* = mc.args.get(i);
        let lit: Option<String*> = is_str_lit(arg);
        if(lit.is_some()){
          let val: String = lit.unwrap().clone();
          let ptr = self.get_global_string(val);
          vector_Value_push(args, ptr);
          continue;
        }
        let arg_type = self.getType(arg);
        if(arg_type.eq("i8*") || arg_type.eq("u8*")){
          let val = self.get_obj_ptr(arg);
          vector_Value_push(args, val);
          arg_type.drop();
          continue;
        }
        if(arg_type.is_prim()){
          let val = self.loadPrim(arg);
          vector_Value_push(args, val);
        }else if(arg_type.is_any_pointer()){
          let val = self.get_obj_ptr(arg);
          vector_Value_push(args, val);
          arg_type.drop();
          continue;
        }else{
          panic("compiler err sprintf arg {:?}", arg_type);
        }
        arg_type.drop();
      }
      let printf_proto = self.protos.get().libc("sprintf");
      let res = CreateCall(printf_proto, args);
      vector_Value_delete(args);
      return res;
    }
  
    func visit_deref(self, node: Expr*, e: Expr*): Value*{
      let type = self.getType(node);
      let val = self.get_obj_ptr(e);
      if (type.is_prim() || type.is_pointer()) {
          let res = self.load(val, &type);
          type.drop();
          return res;
      }
      type.drop();
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
      phi_addIncoming(phi, makeInt(i8val, 8) as Value*, bb);
      phi_addIncoming(phi, rbit, then);
      return Pair::new(CreateZExt(phi as Value*, getInt(8)), next);
    }
    
    func visit_lit(self, expr: Expr*, node: Literal*): Value*{
      match &node.kind{
        LitKind::BOOL => {
          if(node.val.eq("true")) return getTrue();
          return getFalse();
        },
        LitKind::STR => {
          let trg_ptr = self.get_alloc(expr);
          return self.str_lit(node.val.str(), trg_ptr);
        },
        LitKind::CHAR => {
          assert(node.val.len() == 1);
          let chr: i8 = node.val.get(0);
          return makeInt(chr, 32) as Value*;
        },
        LitKind::FLOAT => {
          if(node.suffix.is_some()){
            if(node.suffix.get().eq("f64")){
              let valf: f64 = f64::parse(node.val.str());
              return makeDouble(valf) as Value*;
            }
          }
          let valf: f32 = f32::parse(node.val.str());
          return makeFloat(valf) as Value*;
        },
        LitKind::INT => {
          let bits = 32;
          if (node.suffix.is_some()) {
              bits = self.getSize(node.suffix.get()) as i32;
          }
          let trimmed = node.trim_suffix();
          let normal = trimmed.replace("_", "");
          if (normal.str().starts_with("0x") || normal.str().starts_with("-0x")){
            let val: i64 = i64::parse_hex(normal.str()).unwrap();
            normal.drop();
            return makeInt(val, bits) as Value*;
          }
          let val: i64 = i64::parse(normal.str()).unwrap();
          normal.drop();
          return makeInt(val, bits) as Value*;
        },
      }
    }

    func str_lit(self, val: str, trg_ptr: Value*): Value*{
      let src = self.get_global_string(val.str());
      let str_ty = Type::new("str");
      let stringType = self.mapType(&str_ty) as llvm_Type*;
      let sliceType = self.protos.get().std("slice") as llvm_Type*;
      let slice_ptr = CreateStructGEP(trg_ptr, 0, stringType);
      let data_target = CreateStructGEP(slice_ptr, SLICE_PTR_INDEX(), sliceType);
      let len_target = CreateStructGEP(slice_ptr, SLICE_LEN_INDEX(), sliceType);
      //set ptr
      CreateStore(src, data_target);
      //set len
      let len = makeInt(val.len(), SLICE_LEN_BITS()) as Value*;
      CreateStore(len, len_target);
      str_ty.drop();
      return trg_ptr;
    }
  
    func set_fields(self, ptr: Value*, decl: Decl*,ty: llvm_Type*, args: List<Entry>*, fields: List<FieldDecl>*){
      let field_idx = 0;
      for(let i = 0;i < args.len();++i){
        let arg = args.get(i);
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
        let fd = fields.get(prm_idx);
        if(decl.base.is_some()) ++prm_idx;
        let field_target_ptr = CreateStructGEP(ptr, prm_idx, ty);
        self.setField(&arg.expr, &fd.type, field_target_ptr);
        self.own.get().do_move(&arg.expr);
      }
    }
    func visit_obj(self, node: Expr*, type: Type*, args: List<Entry>*): Value*{
      let ptr = self.get_alloc(node);
      return self.visit_obj(node, type, args, ptr);
    }
    
    func visit_obj(self, node: Expr*, type: Type*, args: List<Entry>*, ptr: Value*): Value*{
        let rt = self.get_resolver().visit(node);
        self.own.get().add_obj(node, ptr, &rt.type);
        let ty = self.mapType(&rt.type);
        let decl = self.get_resolver().get_decl(&rt).unwrap();
        self.cache.inc.depends_decl(self.get_resolver().unit.path.str(), decl);
        
        //set base
        for(let i = 0;i < args.len();++i){
          let arg = args.get(i);
          if(!arg.isBase) continue;
          let base_index = 0;
          if(decl.is_enum()){
            base_index = 1;
          }
          let base_ptr = CreateStructGEP(ptr, base_index, ty);
          let val_ptr = self.visit(&arg.expr);
          let base_ty = self.get_resolver().getType(&arg.expr);
          self.copy(base_ptr, val_ptr, &base_ty);
          base_ty.drop();
          self.own.get().do_move(&arg.expr);
        }
        if let Decl::Struct(fields*)=(decl){
          let field_idx = 0;
          for(let i = 0;i < args.len();++i){
            let arg = args.get(i);
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
            let fd = fields.get(prm_idx);
            if(decl.base.is_some()) ++prm_idx;
            let field_target_ptr = CreateStructGEP(ptr, prm_idx, ty);
            self.setField(&arg.expr, &fd.type, field_target_ptr);
            self.own.get().do_move(&arg.expr);
          }
        }else{
          let variant_index = Resolver::findVariant(decl, type.name());
          let variant = decl.get_variants().get(variant_index);
          //set tag
          let tag_ptr = CreateStructGEP(ptr, get_tag_index(decl), ty);
          let tag_val = makeInt(variant_index, ENUM_TAG_BITS()) as Value*;
          CreateStore(tag_val, tag_ptr);
          //set data
          let data_ptr = CreateStructGEP(ptr, get_data_index(decl), ty);
          let var_ty = self.get_variant_ty(decl, variant);
          self.set_fields(data_ptr, decl, var_ty, args, &variant.fields);
        }
        rt.drop();
        return ptr;
    }

    func visit_infix(self, expr: Expr*, op: String*, l: Expr*, r: Expr*): Value*{
      let rt = self.get_resolver().visit(l);
      let res = self.visit_infix(op, l, r, &rt.type);
      rt.drop();
      return res;
    }

    func visit_infix(self, op: String*, l: Expr*, r: Expr*, type: Type*): Value*{
      if(op.eq("&&") || op.eq("||")){
        return self.andOr(op, l, r).a;
      }
      if(op.eq("=")){
        return self.visit_assign(l, r);
      }
      let rv = self.cast(r, type);
      if(op.eq("+=")){
        let lv = self.get_lhs(l);
        let lval = self.loadPrim(l);
        if(type.is_float()){
          let tmp = CreateFAdd(lval, rv);
          CreateStore(tmp, lv);
          return lv;
        }
        let tmp = CreateNSWAdd(lval, rv);
        CreateStore(tmp, lv);
        return lv;
      }
      if(op.eq("-=")){
        let lv = self.visit(l);
        let lval = self.loadPrim(l);
        if(type.is_float()){
          let tmp = CreateFSub(lval, rv);
          CreateStore(tmp, lv);
          return lv;
        }
        let tmp = CreateNSWSub(lval, rv);
        CreateStore(tmp, lv);
        return lv;
      }
      if(op.eq("*=")){
        let lv = self.visit(l);
        let lval = self.loadPrim(l);
        if(type.is_float()){
          let tmp = CreateFMul(lval, rv);
          CreateStore(tmp, lv);
          return lv;
        }
        let tmp = CreateNSWMul(lval, rv);
        CreateStore(tmp, lv);
        return lv;
      }
      if(op.eq("/=")){
        let lv = self.visit(l);
        let lval = self.loadPrim(l);
        if(type.is_float()){
          let tmp = CreateFDiv(lval, rv);
          CreateStore(tmp, lv);
          return lv;
        }
        let tmp = CreateSDiv(lval, rv);
        CreateStore(tmp, lv);
        return lv;
      }
      let lv = self.cast(l, type);
      if(is_comp(op.str())){
        //todo remove redundant cast
        let op_c = op.clone().cstr();
        if(type.is_float()){
          let res = CreateCmp(get_comp_op_float(op_c.ptr()), lv, rv);
          op_c.drop();
          return res;
        }
        let res = CreateCmp(get_comp_op(op_c.ptr()), lv, rv);
        op_c.drop();
        return res;
      }
      if(op.eq("+")){
        if(type.is_float()){
          return CreateFAdd(lv, rv);
        }
        return CreateNSWAdd(lv, rv);
      }
      if(op.eq("-")){
        if(type.is_float()){
          return CreateFSub(lv, rv);
        }
        return CreateNSWSub(lv, rv);
      }
      if(op.eq("*")){
        if(type.is_float()){
          return CreateFMul(lv, rv);
        }
        return CreateNSWMul(lv, rv);
      }
      if(op.eq("/")){
        if(type.is_float()){
          return CreateFDiv(lv, rv);
        }
        return CreateSDiv(lv, rv);
      }
      if(op.eq("%")){
        if(type.is_float()){
          return CreateFRem(lv, rv);
        }
        return CreateSRem(lv, rv);
      }
      if(op.eq("&")){
        return CreateAnd(lv, rv);
      }
      if(op.eq("|")){
        return CreateOr(lv, rv);
      }
      if(op.eq("^")){
        return CreateXor(lv, rv);
      }
      if(op.eq("<<")){
        return CreateShl(lv, rv);
      }
      if(op.eq(">>")){
        return CreateAShr(lv, rv);
      }
      panic("infix '{}'\n", op);
    }
    
    func get_lhs(self, expr: Expr*): Value*{
      if let Expr::Unary(op*, l2*)=(expr){
        if(op.eq("*")){
          let lhs = self.get_obj_ptr(l2.get());
          return lhs;
        }
      }
      if let Expr::Name(name*)=(expr){
        return self.visit_name(expr, name, false);
      }
      return self.visit(expr);
    }
  
    func visit_assign(self, l: Expr*, r: Expr*): Value*{
      if(l is Expr::Infix) panic("assign lhs");
      //let lhs = Option<Value*>::new();
      let type = self.getType(l);
      if let Expr::Unary(op*,l2*)=(l){
        if(op.eq("*")){
          let lhs = self.get_obj_ptr(l2.get());
          self.setField(r, &type, lhs, Option::new(l));
          self.own.get().do_assign(l, r);
          type.drop();
          return lhs;
        }
      }
      let lhs = self.get_lhs(l);
      //todo setField should free lhs
      self.setField(r, &type, lhs, Option::new(l));
      self.own.get().do_assign(l, r);
      type.drop();
      return lhs;
    }

    func emit_expr(self, expr: Expr*, trg_ptr: Value*){
      let rt = self.get_resolver().visit(expr);
      match expr{
        Expr::Obj(obj_type*, entries*) => {
          self.visit_obj(expr, obj_type, entries, trg_ptr);
        },
        Expr::Lit(lit*) => {
          if(lit.kind is LitKind::STR){
            self.str_lit(lit.val.str(), trg_ptr);
          }else{
            let val = self.visit_lit(expr, lit);
            CreateStore(val, trg_ptr);
          }
        },
        Expr::Call(mc*) => {
          if(is_struct(&rt.type)){
            self.visit_call2(expr, mc, Option::new(trg_ptr), rt);
          }else{
            let val = self.visit_call2(expr, mc, Option<Value*>::new(), rt);
            CreateStore(val, trg_ptr);
          }
          return;//rt is moved,return
        },
        Expr::Array(list*, size*) => {
          if(!Compiler::is_constexpr(expr)){
            //AllocHelper::new(self).visit_child(expr);
            self.visit_array(expr, list, size, trg_ptr);
          }else{
            panic("glob rhs arr '{:?}'", expr);
          }
        },
        _ => {
          panic("glob rhs '{:?}'", expr);
        },
      }
      rt.drop();
    }
}//end impl Compiler


func is_deref(expr: Expr*): Option<Expr*>{
  if let Expr::Unary(op*, e*)=(expr){
      if(op.eq("*")) return Option::new(e.get());
  }
  return Option<Expr*>::new();
}