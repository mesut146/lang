import std/map
import std/stack

import ast/ast
import ast/utils
import ast/printer

import resolver/resolver
import resolver/derive
import resolver/drop_helper

import backend/compiler
import backend/stmt_emitter
//import backend/llvm
import backend/debug_helper
import backend/compiler_helper
import backend/bridge
import parser/ownership
import parser/own_model

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
      let ll = self.ll.get();
      self.di.get().loc(node.line, node.pos);
      match node{
        Expr::Call(mc) => return self.visit_call(node, mc),
        Expr::MacroCall(mc) => return self.visit_macrocall(node, mc),
        Expr::ArrAccess(aa) => return self.visit_array_access(node, aa),
        Expr::Array(list, sz) => return self.visit_array(node, list, sz),
        Expr::Access(scope, name) => return self.visit_access(node, scope.get(), name),
        Expr::Par(e) => return self.visit(e.get()),
        Expr::Obj(type, args) => return self.visit_obj(node, type, args),
        Expr::Lit(lit) => return self.visit_lit(node, lit),
        Expr::Infix(op, l, r) => return self.visit_infix(node, op, l.get(), r.get()),
        Expr::Name(name) => return self.visit_name(node, name, true),
        Expr::Is(lhs, rhs) => return self.visit_is(lhs.get(), rhs.get()),
        Expr::As(lhs, rhs) => return self.visit_as(lhs.get(), rhs),
        Expr::If(is) => {
          let res = self.visit_if(is.get());
          if(res.is_none()){
            return self.nullptr();
          }
          return res.unwrap();
        },
        Expr::IfLet(is) => {
          let res = self.visit_iflet(node.line, is.get());
          if(res.is_none()){
            return self.nullptr();
          }
          return res.unwrap();
        },
        Expr::Block(b) => {
          let res = self.visit_block(b.get());
          if(res.is_none()){
            return self.nullptr();
          }
          return res.unwrap();
        },
        Expr::Unary(op, e) => {
          if(op.eq("&")){
            return self.visit_ref(node, e.get());
          }
          if(op.eq("*")){
            return self.visit_deref(node, e.get());
          }
          return self.visit_unary(op, e.get());
        },
        Expr::Type(type) => {
            let r = self.get_resolver();
            let rt = r.visit(node);
            if(rt.type.is_fpointer() && rt.method_desc.is_some()){
                let target: Method* = r.get_method(&rt).unwrap();
                let proto = self.protos.get().get_func(target);
                rt.drop();
                return proto.val as Value*;
            }
            rt.drop();
            return self.simple_enum(node, type);
        },
        Expr::Match(me) => {
          let res = self.visit_match(node, me.get());
          if(res.is_none()){
            return self.nullptr();
          }
          return res.unwrap();
        },
        Expr::Lambda(le) => {
            let r = self.get_resolver();
            let m = r.lambdas.get(&node.id).unwrap();
            let proto = self.protos.get().get_func(m);
            
            return proto.val as Value*;
        },
        Expr::Ques(bx) => {
          let r = self.get_resolver();
          let info = r.get_macro(node);
          return self.visit_block(&info.block).unwrap();
        },
        Expr::Tuple(elems) => {
          let r = self.get_resolver();
          let node_type = r.getType(node);
          let ty = self.mapType(&node_type);
          let ptr = self.get_alloc(node);
          for(let i = 0;i < elems.len();++i){
            let elem = elems.get(i);
            let elem_ty = r.getType(elem);
            let field_target_ptr = CreateStructGEP(ll.builder, ty, ptr, i);
            self.setField(elem, &elem_ty, field_target_ptr);
            elem_ty.drop();
          }
          node_type.drop();
          return ptr;
        }
      }
    }
    
    func nullptr(self): Value*{
      //let vptr = getPointerTo(getVoidTy(self.ll.get().builder));
      //let vptr = getPtr(self.ll.get().ctx) as PointerType*;
      let vptr = self.ll.get().intPtr(8) as PointerType*;
      return ConstantPointerNull_get(vptr);
    }

    func get_variant_index_match(lhs_ty: Type*, decl: Decl*): i32{
      let idx = 0;
      let name: String* = lhs_ty.name();
      for ev in decl.get_variants(){
        if(ev.name.eq(name)){
          return idx;
        }
        ++idx;
      }
      panic("idx {:?} {:?}", lhs_ty, decl.type);
    }

    func visit_match_rhs(self, rhs: MatchRhs*): Option<Value*>{
      match rhs{
        MatchRhs::EXPR(e)=>{
          return Option<Value*>::new(self.visit(e));
        },
        MatchRhs::STMT(st)=>{
          self.visit(st);
          return Option<Value*>::new();
        }
      }
    }

    func visit_match(self, expr: Expr*, node: Match*): Option<Value*>{
      let ll = self.ll.get();
      let resolver = self.get_resolver();
      let rhs_rt = resolver.visit(&node.expr);
      let decl = resolver.get_decl(&rhs_rt).unwrap();
      let rhs = self.get_obj_ptr(&node.expr);
      let tag_ptr = CreateStructGEP(ll.builder, self.mapType(&decl.type), rhs, get_tag_index(decl));
      let tag = CreateLoad(ll.builder, intTy(ll.ctx, ENUM_TAG_BITS()), tag_ptr);

      let next_name = format("next_{}", expr.line).cstr();
      let def_name = format("def_{}", expr.line).cstr();
      let nextbb = create_bb(ll.ctx, next_name.ptr(), self.cur_func());
      let def_bb = create_bb(ll.ctx, def_name.ptr(), self.cur_func());
      let sw = CreateSwitch(ll.builder, tag, def_bb, node.cases.len() as i32);
      let match_rt = resolver.visit(expr);
      let match_type = match_rt.unwrap();
      let none_case = node.has_none();
      if(none_case.is_none()){
        SetInsertPoint(ll.builder, def_bb);
        CreateUnreachable(ll.builder);
      }
      //create bb's
      let res = Option<Value*>::new();
      let infos = List<MatchInfo>::new();
      let use_next = false;
      for case in &node.cases{
        match &case.lhs{
          MatchLhs::NONE => {
            SetInsertPoint(ll.builder, def_bb);
            let rhs_val = self.visit_match_rhs(&case.rhs);
            let exit = Exit::get_exit_type(&case.rhs);
            if(!exit.is_jump()){
                CreateBr(ll.builder, nextbb);
                use_next = true;
                if(!match_type.is_void()){
                  let rt2 = resolver.visit_match_rhs(&case.rhs);
                  infos.add(MatchInfo{rt2.unwrap(), rhs_val.unwrap(), def_bb});
                }
            }
          },
          MatchLhs::ENUM(type, args) => {
            let name_c = format("{:?}__{}_{}", decl.type, type.name(), expr.line).cstr();
            let bb = create_bb(ll.ctx, name_c.ptr(), self.cur_func());
            let var_index = get_variant_index_match(type, decl);
            SwitchInst_addCase(sw, ll.makeInt(var_index, 64) as ConstantInt*, bb);
            SetInsertPoint(ll.builder, bb);
            //alloc args
            let variant = decl.get_variants().get(var_index);
            let arg_idx = 0;
            for arg in args{
              self.alloc_enum_arg(arg, variant, arg_idx, decl, rhs, &rhs_rt.type);
              ++arg_idx;
            }
            self.own.get().add_scope(ScopeType::MATCH_CASE, &case.rhs);
            let rhs_val = self.visit_match_rhs(&case.rhs);
            self.own.get().end_scope(Compiler::get_end_line(&case.rhs));
            let rhs_end_bb = GetInsertBlock(ll.builder);
            let exit = Exit::get_exit_type(&case.rhs);
            if(!exit.is_jump()){
              if(!match_type.is_void()){
                let rt2 = resolver.visit_match_rhs(&case.rhs);
                let val = rhs_val.unwrap();
                if(!is_struct(&match_type)){
                    //fix
                    if(match_type.is_prim() && Value_isPointerTy(val)){
                        val = CreateLoad(ll.builder, self.mapType(&match_type), val);
                    }
                    val = self.cast2(val, &rt2.type, &match_type);
                }
                rhs_val.set(val);
                infos.add(MatchInfo{rt2.unwrap(), rhs_val.unwrap(), rhs_end_bb});
              }
              CreateBr(ll.builder, nextbb);
              use_next = true;
            }
            name_c.drop();
          },
          MatchLhs::UNION(types) => {
            let name_c = format("{:?}__$union_{}", decl.type, expr.line).cstr();
            let bb = create_bb(ll.ctx, name_c.ptr(), self.cur_func());
            for uty in types{
              //all variants go to bb
              let var_index = get_variant_index_match(uty, decl);
              SwitchInst_addCase(sw, ll.makeInt(var_index, 64) as ConstantInt*, bb);
            }
            SetInsertPoint(ll.builder, bb);

            self.own.get().add_scope(ScopeType::MATCH_CASE, &case.rhs);
            let rhs_val = self.visit_match_rhs(&case.rhs);
            self.own.get().end_scope(Compiler::get_end_line(&case.rhs));
            let rhs_end_bb = GetInsertBlock(ll.builder);
            let exit = Exit::get_exit_type(&case.rhs);
            if(!exit.is_jump()){
              if(!match_type.is_void()){
                let rt2 = resolver.visit_match_rhs(&case.rhs);
                let val = rhs_val.unwrap();
                if(!is_struct(&match_type)){
                    //fix
                    if(match_type.is_prim() && Value_isPointerTy(val)){
                        val = CreateLoad(ll.builder, self.mapType(&match_type), val);
                    }
                    val = self.cast2(val, &rt2.type, &match_type);
                }
                rhs_val.set(val);
                infos.add(MatchInfo{rt2.unwrap(), rhs_val.unwrap(), rhs_end_bb});
              }
              CreateBr(ll.builder, nextbb);
              use_next = true;
            }
          }
        }
      }
      if(use_next){
        SetInsertPoint(ll.builder, nextbb);
      }else{
        //LLVMDeleteBasicBlock(nextbb);
        SetInsertPoint(ll.builder, nextbb);
        CreateUnreachable(ll.builder);
      }
      //handle ret value
      if(!infos.empty()){
        let phi_type = self.mapType(&match_type);
        if(is_struct(&match_type)){
          phi_type = getPointerTo(phi_type) as llvm_Type*;
        }
        let phi = CreatePHI(ll.builder, phi_type, infos.len() as i32);
        for info in &infos{
          phi_addIncoming(phi, info.val, info.bb);
        }
        res = Option::new(phi as Value*);
      }
      def_name.drop();
      next_name.drop();
      rhs_rt.drop();
      return res;
    }

    func alloc_enum_arg(self, arg: ArgBind*, variant: Variant*, arg_idx: i32, decl: Decl*, enum_ptr: Value*, rhs_ty: Type*){
      let ll = self.ll.get();
      let data_index = get_data_index(decl);
      let dataPtr = CreateStructGEP(ll.builder, self.mapType(&decl.type), enum_ptr, data_index);
      let var_ty = self.get_variant_ty(decl, variant);

      let field = variant.fields.get(arg_idx);
      let alloc_ptr = self.get_alloc(arg.id);
      self.NamedValues.add(arg.name.clone(), alloc_ptr);
      let gep_idx = arg_idx;
      if(decl.base.is_some()){
        ++gep_idx;
      }
      let field_ptr = CreateStructGEP(ll.builder, var_ty, dataPtr, gep_idx);
      if (rhs_ty.is_pointer()) {
        CreateStore(ll.builder, field_ptr, alloc_ptr);
        let ty_ptr = field.type.clone().toPtr();
        self.di.get().dbg_var(&arg.name, &ty_ptr, arg.line, self);
        ty_ptr.drop();
      }else {
        //deref
        if (field.type.is_prim() || field.type.is_any_pointer()) {
            let field_val = CreateLoad(ll.builder, self.mapType(&field.type), field_ptr);
            CreateStore(ll.builder, field_val, alloc_ptr);
        } else {
            //DropHelper::new(self.get_resolver()).is_drop_type(&node.rhs), delete this after below works
            self.copy(alloc_ptr, field_ptr, &field.type);
            self.own.get().add_iflet_var(arg, field, LLVMPtr::new(alloc_ptr));
        }
        self.di.get().dbg_var(&arg.name, &field.type, arg.line, self);
      }      
    }

    func is_nested_if(body: Body*): bool{
      if(body is Body::If || body is Body::IfLet) return true;
      if let Body::Block(blk) = body{
        if(blk.return_expr.is_some()){
          return is_if(blk.return_expr.get());
        }
      }
      return false;
    }
    func is_if(expr: Expr*): bool{
      return expr is Expr::If || expr is Expr::IfLet;
    }

    func visit_if(self, node: IfStmt*): Option<Value*>{
      let ll = self.ll.get();
      let cond = self.branch(&node.cond);
      let line = node.cond.line;
      let then_name = CStr::new(format("if_then_{}", line));
      let else_name = CStr::new(format("if_else_{}", line));
      let next_name = CStr::new(format("if_next_{}", line));
      let thenbb = create_bb(ll.ctx, then_name.ptr(), self.cur_func());
      let elsebb = create_bb(ll.ctx, else_name.ptr(), self.cur_func());
      let nextbb = create_bb(ll.ctx, next_name.ptr(), self.cur_func());
      CreateCondBr(ll.builder, cond, thenbb, elsebb);
      SetInsertPoint(ll.builder, thenbb);
      self.di.get().new_scope(node.then.get().line());
      let exit_then = Exit::get_exit_type(node.then.get());
      let if_id = self.own.get().add_scope(ScopeType::IF, node.then.get());
      let then_val = self.visit_body(node.then.get());
      let then_end = GetInsertBlock(ll.builder);
      let else_end = GetInsertBlock(ll.builder);
      //else move aware end_scope
      if(node.else_stmt.is_some()){
        self.own.get().end_scope_if(&node.else_stmt, Compiler::get_end_line(node.then.get()));
      }else{
        self.own.get().end_scope(Compiler::get_end_line(node.then.get()));
      }
      self.di.get().exit_scope();
      if(!exit_then.is_jump()){
        CreateBr(ll.builder, nextbb);
      }
      SetInsertPoint(ll.builder, elsebb);
      let else_jump = false;
      let else_val = Option<Value*>::new();
      
      if(node.else_stmt.is_some()){
        self.di.get().new_scope(node.else_stmt.get().line());
        //this will restore if, bc we did fake end_scope
        let else_id = self.own.get().add_scope(ScopeType::ELSE, node.else_stmt.get());
        self.own.get().get_scope(else_id).sibling = if_id;
        else_val = self.visit_body(node.else_stmt.get());
        else_end = GetInsertBlock(ll.builder);
        self.own.get().end_scope(Compiler::get_end_line(node.else_stmt.get()));
        self.di.get().exit_scope();
        let exit_else = Exit::get_exit_type(node.else_stmt.get());
        else_jump = exit_else.is_jump();
        if(!else_jump){
          CreateBr(ll.builder, nextbb);
        }
        exit_else.drop();
      }else{
        let else_id = self.own.get().add_scope(ScopeType::ELSE, line, Exit::new(ExitType::NONE), true);
        self.own.get().get_scope(else_id).sibling = if_id;
        self.own.get().end_scope(Compiler::get_end_line(node.then.get()));
        CreateBr(ll.builder, nextbb);
      }
      let res = Option<Value*>::new();
      if(!(exit_then.is_jump() && else_jump)){
        SetInsertPoint(ll.builder, nextbb);
        let then_rt = self.get_resolver().visit_body(node.then.get());
        if(!then_rt.type.is_void()){
          //if(is_nested_if(node.then.get()) || is_nested_if(node.else_stmt.get())){
            //self.get_resolver().err(line, "nested if expr not allowed");
          //}
          if(exit_then.is_jump() && !else_jump){
            res = else_val;
          }
          else if(!exit_then.is_jump() && else_jump){
            res = then_val;
          }else{
            let phi_type = self.mapType(&then_rt.type);
            if(is_struct(&then_rt.type)){
              phi_type = getPointerTo(phi_type) as llvm_Type*;
            }
            let phi = CreatePHI(ll.builder, phi_type, 2);
            if(is_struct(&then_rt.type)){
              phi_addIncoming(phi, then_val.unwrap(), then_end);
              phi_addIncoming(phi, else_val.unwrap(), else_end);
            }else{
              phi_addIncoming(phi, self.loadPrim(then_val.unwrap(), &then_rt.type), then_end);
              phi_addIncoming(phi, self.loadPrim(else_val.unwrap(), &then_rt.type), else_end);
            }
            res = Option::new(phi as Value*);
          }
        }
        then_rt.drop();
      }else{
        //LLVMDeleteBasicBlock(nextbb);
        SetInsertPoint(ll.builder, nextbb);
        CreateUnreachable(ll.builder);
      }
      exit_then.drop();
      then_name.drop();
      else_name.drop();
      next_name.drop();
      return res;
    }

    func visit_iflet(self, line: i32, node: IfLet*): Option<Value*>{
      let ll = self.ll.get();
      let rt = self.get_resolver().visit_type(&node.type);
      let decl = self.get_resolver().get_decl(&rt).unwrap();
      let rhs = self.get_obj_ptr(&node.rhs);
      let rhs_rt = self.get_resolver().visit(&node.rhs);
      let tag_ptr = CreateStructGEP(ll.builder, self.mapType(&decl.type), rhs, get_tag_index(decl));
      let tag = CreateLoad(ll.builder, intTy(ll.ctx, ENUM_TAG_BITS()), tag_ptr);
      let index = Resolver::findVariant(decl, node.type.name());
      let cmp = CreateCmp(ll.builder, get_comp_op("==".ptr()), tag, ll.makeInt(index, ENUM_TAG_BITS()));
  
      let then_name = CStr::new(format("iflet_then_{}", line));
      let else_name = CStr::new(format("iflet_else_{}", line));
      let next_name = CStr::new(format("iflet_next_{}", line));
      let then_bb = create_bb(ll.ctx, then_name.ptr(), self.cur_func());
      let elsebb = create_bb(ll.ctx, else_name.ptr(), self.cur_func());
      let next = create_bb(ll.ctx, next_name.ptr(), self.cur_func());
      
      CreateCondBr(ll.builder, self.branch(cmp), then_bb, elsebb);
      SetInsertPoint(ll.builder, then_bb);
      let if_id = self.own.get().add_scope(ScopeType::IF, node.then.get());
      self.own.get().do_move(&node.rhs);
      let variant = decl.get_variants().get(index);
      self.di.get().new_scope(line);
      if(!variant.fields.empty()){
        //declare vars
        let fields = &variant.fields;
        let data_index = get_data_index(decl);
        let dataPtr = CreateStructGEP(ll.builder, self.mapType(&decl.type), rhs, data_index);
        let var_ty = self.get_variant_ty(decl, variant);
        for (let i = 0; i < fields.size(); ++i) {
            //regular var decl
            let prm = fields.get(i);
            let arg = node.args.get(i);
            self.alloc_enum_arg(arg, variant, i, decl, rhs, &rhs_rt.type);
        }
      }
      let then_val = self.visit_body(node.then.get());
      let then_end = GetInsertBlock(ll.builder);
      let else_end = GetInsertBlock(ll.builder);
      //else move aware end_scope
      if(node.else_stmt.is_some()){
        self.own.get().end_scope_if(&node.else_stmt, Compiler::get_end_line(node.then.get()));
      }else{
        self.own.get().end_scope(Compiler::get_end_line(node.then.get()));
      }
      self.di.get().exit_scope();
      let exit_then = Exit::get_exit_type(node.then.get());
      if (!exit_then.is_jump()) {
        CreateBr(ll.builder, next);
      }
      SetInsertPoint(ll.builder, elsebb);
      let else_jump = false;
      let else_val = Option<Value*>::new();
      if (node.else_stmt.is_some()) {
        self.di.get().new_scope(node.else_stmt.get().line());
        let else_id = self.own.get().add_scope(ScopeType::ELSE, node.else_stmt.get());
        self.own.get().get_scope(else_id).sibling = if_id;
        else_val = self.visit_body(node.else_stmt.get());
        else_end = GetInsertBlock(ll.builder);
        self.own.get().end_scope(Compiler::get_end_line(node.else_stmt.get()));
        self.di.get().exit_scope();
        let exit_else = Exit::get_exit_type(node.else_stmt.get());
        else_jump = exit_else.is_jump();
        if (!else_jump) {
          CreateBr(ll.builder, next);
        }
        exit_else.drop();
      }else{
        let else_id = self.own.get().add_scope(ScopeType::ELSE, line, Exit::new(ExitType::NONE), true);
        self.own.get().get_scope(else_id).sibling = if_id;
        self.own.get().end_scope(Compiler::get_end_line(node.then.get()));
        CreateBr(ll.builder, next);
      }
      let res = Option<Value*>::new();
      if(!(exit_then.is_jump() && else_jump)){
        SetInsertPoint(ll.builder, next);

        let then_rt = self.get_resolver().visit_body(node.then.get());
        if(!then_rt.type.is_void()){
          //if(is_nested_if(node.then.get()) || is_nested_if(node.else_stmt.get())){
            //self.get_resolver().err(line, "nested if expr not allowed");
          //}
          if(exit_then.is_jump() && !else_jump){
            res = else_val;
          }
          else if(!exit_then.is_jump() && else_jump){
            res = then_val;
          }else{
            let phi_type = self.mapType(&then_rt.type);
            if(is_struct(&then_rt.type)){
              phi_type = getPointerTo(phi_type) as llvm_Type*;
            }
            let phi = CreatePHI(ll.builder, phi_type, 2);
            if(is_struct(&then_rt.type)){
              phi_addIncoming(phi, then_val.unwrap(), then_end);
              phi_addIncoming(phi, else_val.unwrap(), else_end);
            }else{
              phi_addIncoming(phi, self.loadPrim(then_val.unwrap(), &then_rt.type), then_end);
              phi_addIncoming(phi, self.loadPrim(else_val.unwrap(), &then_rt.type), else_end);
            }
            res = Option::new(phi as Value*);
          }
        }
        then_rt.drop();
      }else{
        //LLVMDeleteBasicBlock(next);
        SetInsertPoint(ll.builder, next);
        CreateUnreachable(ll.builder);
      }
      exit_then.drop();
      then_name.drop();
      else_name.drop();
      next_name.drop();
      rt.drop();
      rhs_rt.drop();
      return res;
    }

    func visit_name(self, node: Expr*, name: String*, check: bool): Value*{
      let rt = self.get_resolver().visit(node);
      if(rt.desc.kind is RtKind::Const){
        let cn = self.get_resolver().get_const(&rt);
        match &cn.rhs{
          Expr::Lit(lit) => {
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
          return proto.val as Value*;
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
        //CreateStore(ll.builder, val, alloc_ptr);
        let expr_type = self.get_resolver().getType(expr);
        self.setField(expr, &expr_type, alloc_ptr);
        self.own.get().add_obj(node, LLVMPtr::new(alloc_ptr), &expr_type);
        expr_type.drop();
        return alloc_ptr;
      }
      let inner = self.visit(expr);
      return inner;
    }

    func visit_repr(self, lhs: Expr*, rhs: Type*): Value*{
      match lhs{
        Expr::Name(nm)=>{
          let res = self.get_obj_ptr(lhs);
          res = self.loadPrim(res, rhs);
          return res;
        },
        Expr::Type(ty)=>{
          let res = self.visit(lhs);
          res = self.loadPrim(res, rhs);
          return res;
        },
        _=> {}
      }
      panic("todo {:?} as {:?}", lhs, rhs);
    }
  
    func visit_as(self, lhs: Expr*, rhs: Type*): Value*{
      let ll = self.ll.get();
      let lhs_rt = self.get_resolver().visit(lhs);
      //ptr to int
      if (lhs_rt.type.is_any_pointer() && rhs.eq("u64")) {
        let val = self.get_obj_ptr(lhs);
        lhs_rt.drop();
        return CreatePtrToInt(ll.builder, val, self.mapType(rhs));
      }
      //prim to prim
      let rhs_rt = self.get_resolver().visit_type(rhs);
      if (lhs_rt.type.is_prim() && rhs.is_prim()) {
        let res = self.cast(lhs, &rhs_rt.type);
        lhs_rt.drop();
        rhs_rt.drop();
        return res;
      }
      //enum -> base
      if(lhs_rt.is_decl()){
        let decl = self.get_resolver().get_decl(&lhs_rt).unwrap();
        //enum repr -> int
        if(decl.is_enum() && decl.is_repr() && rhs.is_prim()){
          let val = self.visit_repr(lhs, &rhs_rt.type);
          lhs_rt.drop();
          rhs_rt.drop();
          return val;
        }
        if(decl.is_enum() && rhs_rt.is_decl()){
          let val = self.get_obj_ptr(lhs);
          val = CreateStructGEP(ll.builder, self.mapType(&decl.type), val, get_data_index(decl));
          lhs_rt.drop();
          rhs_rt.drop();
          return val;
        }
      }
      let val = self.get_obj_ptr(lhs);
      lhs_rt.drop();
      rhs_rt.drop();
      return val;
    }
  
    func visit_is(self, lhs: Expr*, rhs: Expr*): Value*{
      let ll = self.ll.get();
      let tag1 = self.getTag(lhs);
      let op = get_comp_op("==".ptr());
      if let Expr::Type(rhs_ty) = rhs{
        let decl = self.get_resolver().get_decl(rhs_ty).unwrap();
        let index = Resolver::findVariant(decl, rhs_ty.name());
        let tag2 = ll.makeInt(index, ENUM_TAG_BITS()) ;
        return CreateCmp(ll.builder, op, tag1, tag2);
      }
      let tag2 = self.getTag(rhs);
      return CreateCmp(ll.builder, op, tag1, tag2);
    }

    func simple_enum(self, node: Expr*, type: Type*): Value*{
      let ptr = self.get_alloc(node);
      return self.simple_enum(type, ptr);
    }
  
    func simple_enum(self, type: Type*, ptr: Value*): Value*{
      let ll = self.ll.get();
      let smp = type.as_simple();
      let decl = self.get_resolver().get_decl(smp.scope.get()).unwrap();
      let index = Resolver::findVariant(decl, &smp.name);
      if(decl.is_repr()){
        let at = decl.attr.find("repr").unwrap().args.get(0).print();
        let desc = decl.get_variants().get(index).disc.unwrap();
        CreateStore(ll.builder, ll.makeInt(desc, prim_size(at.str()).unwrap() as i32) , ptr);
        at.drop();
        return ptr;
      }
      
      let decl_ty = self.mapType(&decl.type);
      let tag_ptr = CreateStructGEP(ll.builder,  decl_ty, ptr,  get_tag_index(decl));
      CreateStore(ll.builder, ll.makeInt(index, ENUM_TAG_BITS()) , tag_ptr);
      return ptr;
    }
  
    func visit_access(self, node: Expr*, scope: Expr*, name: String*): Value*{
      let ll = self.ll.get();
      let scope_ptr = self.get_obj_ptr(scope);
      let scope_rt = self.get_resolver().visit(scope);
      if let Type::Tuple(tt) = &scope_rt.type {
        let idx = i32::parse(name.str()).expect("tuple index parse error");
        let scope_ty = self.mapType(&scope_rt.type);
        let res = CreateStructGEP(ll.builder, scope_ty, scope_ptr, idx);
        scope_rt.drop();
        return res;
      }
      let decl = self.get_resolver().get_decl(&scope_rt).unwrap();
      if(decl.is_enum()){
        //base field, skip tag
        let ty = self.mapType(&decl.type);
        scope_ptr = CreateStructGEP(ll.builder,  ty, scope_ptr,  get_data_index(decl));
      }
      let pair = self.get_resolver().findField(node, name, decl, &decl.type);
      let index = pair.b;
      if (pair.a.base.is_some()) ++index;
      let sd_ty = self.mapType(&pair.a.type);
      scope_rt.drop();
      return CreateStructGEP(ll.builder,  sd_ty, scope_ptr,  index);
    }
  
    func visit_array(self, node: Expr*, list: List<Expr>*, sz: Option<i32>*): Value*{
      let ptr = self.get_alloc(node);
      return self.visit_array(node, list, sz, ptr);
    }
    func visit_array(self, node: Expr*, list: List<Expr>*, sz: Option<i32>*, ptr: Value*): Value*{
      let ll = self.ll.get();
      let arrt = self.getType(node);
      self.own.get().add_obj(node, LLVMPtr::new(ptr), &arrt);
      let arr_ty = self.mapType(&arrt);
      arrt.drop();
      if(sz.is_none()){
        for(let i = 0;i < list.len();++i){
          let e = list.get(i);
          // let elem_target = gep_arr(arr_ty, ptr, 0, i);
          let elem_target = self.ll.get().gep_arr(arr_ty, ptr, 0, i);
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
      let bb = GetInsertBlock(ll.builder);
      let cur = self.ll.get().gep_arr(arr_ty, ptr, 0, 0);
      let end = self.ll.get().gep_arr(arr_ty, ptr, 0, *sz.get());
      //create cons and memcpy
      let condbb = create_bb(ll.ctx, "".ptr(), self.cur_func());
      let setbb = create_bb(ll.ctx, "".ptr(), self.cur_func());
      let nextbb = create_bb(ll.ctx, "".ptr(), self.cur_func());
      CreateBr(ll.builder, condbb);
      SetInsertPoint(ll.builder, condbb);
      let phi_ty = getPointerTo(elem_ty) as llvm_Type*;
      let phi = CreatePHI(ll.builder, phi_ty, 2);
      phi_addIncoming(phi, cur, bb);
      let ne = CreateCmp(ll.builder, get_comp_op("!=".ptr()), phi as Value*, end);
      CreateCondBr(ll.builder, ne, setbb, nextbb);
      SetInsertPoint(ll.builder, setbb);
      if (elem_ptr.is_some()) {
          self.copy(phi as Value*, elem_ptr.unwrap(), &elem_type);
      } else {
          self.setField(elem, &elem_type, phi as Value*);
      }
      let step = ll.gep_ptr(elem_ty, phi as Value*, ll.makeInt(1, 64));
      phi_addIncoming(phi, step, setbb);
      CreateBr(ll.builder, condbb);
      SetInsertPoint(ll.builder, nextbb);
      elem_type.drop();
      return ptr;
    }
  
    func visit_array_access(self, expr: Expr*, node: ArrAccess*): Value*{
      let ll = self.ll.get();
      if(node.idx2.is_some()){
        return self.visit_slice(expr, node);
      }
      let i64t = Type::new("i64");
      let type = self.getType(node.arr.get());
      let ty = type.deref_ptr();
      let src = self.get_obj_ptr(node.arr.get());
      if(ty.is_array()){
        //regular array access
        let i1 = ll.makeInt(0, 64) ;
        let i2 = self.cast(node.idx.get(), &i64t);
        let res = ll.gep_arr(self.mapType(ty), src, i1, i2);
        type.drop();
        i64t.drop();
        return res ;
      }
      
      //slice access
      let elem = ty.elem();
      let elemty = self.mapType(elem);
      //read array ptr
      let sliceType = self.protos.get().std("slice");
      let arr = CreateStructGEP(ll.builder,  sliceType, src,  SLICE_PTR_INDEX());
      arr = ll.loadPtr(arr);
      let index = self.cast(node.idx.get(), &i64t);
      i64t.drop();
      type.drop();
      return self.ll.get().gep_ptr(elemty, arr, index);
    }

    func visit_slice(self, expr: Expr*, node: ArrAccess*): Value*{
      let ptr = self.get_alloc(expr);
      return self.visit_slice(expr, node, ptr);
    }

    func visit_slice(self,expr: Expr*, node: ArrAccess*, ptr: Value*): Value*{
      let ll = self.ll.get();
      let arr = self.visit(node.arr.get());
      let arr_ty = self.getType(node.arr.get());
      if(arr_ty.is_slice()){
        arr = ll.loadPtr(arr);
      }else if(arr_ty.is_pointer()){
        arr = ll.loadPtr(arr);
      }
      let elem_ty = arr_ty.elem();
      let i32_ty = Type::new("i32");
      let val_start = self.cast(node.idx.get(), &i32_ty);
      let ptr_ty = self.mapType(elem_ty);
      //shift by start
      arr = self.ll.get().gep_ptr(ptr_ty, arr, val_start);
  
      let sliceType = self.protos.get().std("slice");
  
      let trg_ptr = CreateStructGEP(ll.builder, sliceType, ptr, 0);
      let trg_len = CreateStructGEP(ll.builder, sliceType, ptr, 1);
      //store ptr
      CreateStore(ll.builder, arr, trg_ptr);
      //set len
      let val_end = self.cast(node.idx2.get(), &i32_ty);
      let len = CreateSub(ll.builder, val_end, val_start);
      len = CreateSExt(ll.builder, len, intTy(ll.ctx, SLICE_LEN_BITS()));
      CreateStore(ll.builder, len, trg_len);
      arr_ty.drop();
      i32_ty.drop();
      return ptr;
    }

    func makeFloat_one(type: Type*, ll: Emitter2*): Value*{
      if(type.eq("f32")){
        return ll.makeFloat(1.0) as Value*;
      }
      return ll.makeDouble(1.0) as Value*;
    }
  
    func visit_unary(self, op: String*, e: Expr*): Value*{
      let ll = self.ll.get();
      let val = self.loadPrim(e);
      if(op.eq("+")) return val;
      if(op.eq("!")){
        val = CreateTrunc(ll.builder, val, intTy(ll.ctx, 1));
        val = CreateXor(ll.builder, val, getTrue(ll.builder));
        return CreateZExt(ll.builder, val, intTy(ll.ctx, 8));
      }
      let bits = self.ll.get().sizeOf(val) as i32;
      let type = self.getType(e);
      if(op.eq("-")){
        if(type.is_float()){
          type.drop();
          return CreateFNeg(ll.builder, val);
        }
        type.drop();
        return CreateNSWSub(ll.builder, ll.makeInt(0, bits), val);
      }
      if(op.eq("++")){
        let var_ptr = self.visit(e);//var without load
        if(type.is_float()){
          let res = CreateFAdd(ll.builder, val, makeFloat_one(&type, ll));
          CreateStore(ll.builder, res, var_ptr);
          return res;
        }
        if(type.is_unsigned()){
          let res = CreateAdd(ll.builder, val, ll.makeInt(1, bits));
          CreateStore(ll.builder, res, var_ptr);
          return res;
        }
        let res = CreateNSWAdd(ll.builder, val, ll.makeInt(1, bits));
        CreateStore(ll.builder, res, var_ptr);
        return res;
      }
      if(op.eq("--")){
        let var_ptr = self.visit(e);//var without load
        if(type.is_float()){
          let res = CreateFSub(ll.builder, val, makeFloat_one(&type, ll));
          CreateStore(ll.builder, res, var_ptr);
          return res;
        }
        let res = CreateNSWSub(ll.builder, val, ll.makeInt(1, bits));
        CreateStore(ll.builder, res, var_ptr);
        return res;
      }
      if(op.eq("~")){
        return CreateXor(ll.builder, val, ll.makeInt(-1, bits));
      }
      panic("unary {}", op);
    }

    func is_drop_call2(mc: Call*): bool{
      return mc.name.eq("drop") && mc.scope.is_some() && mc.args.empty();
    }

    func visit_macrocall(self, expr: Expr*, mc: MacroCall*): Value*{
        let resolver = self.get_resolver();
        let ll = self.ll.get();
        if(Utils::is_call(mc, "ptr", "deref")){
          let arg_ptr = self.get_obj_ptr(mc.args.get(0));
          let type = self.getType(expr);
          if (!is_struct(&type)) {
              let res = CreateLoad(ll.builder, self.mapType(&type), arg_ptr);
              type.drop();
              return res;
          }
          type.drop();
          return arg_ptr;
        }
        if(Utils::is_call(mc, "ptr", "get")){
          let elem_type = self.getType(expr);
          let src = self.get_obj_ptr(mc.args.get(0));
          let idx = self.loadPrim(mc.args.get(1));
          let res = self.ll.get().gep_ptr(self.mapType(elem_type.deref_ptr()), src, idx);
          elem_type.drop();
          return res;
        }
        if(Utils::is_call(mc, "ptr", "copy")){
          //ptr::copy(src_ptr, src_idx, elem)
          let src_ptr = self.get_obj_ptr(mc.args.get(0));
          let i64_ty = Type::new("i64");
          let idx = self.cast(mc.args.get(1), &i64_ty);
          i64_ty.drop();
          let val = self.visit(mc.args.get(2));
          let elem_type: Type = self.getType(mc.args.get(2));
          let trg_ptr = self.ll.get().gep_ptr(self.mapType(&elem_type), src_ptr, idx);
          self.copy(trg_ptr, val, &elem_type);
          elem_type.drop();
          return ptr::null<Value>();
        }
        if(Utils::is_call(mc, "std", "unreachable")){
          CreateUnreachable(ll.builder);
          return ptr::null<Value>();
        }
        if(Utils::is_call(mc, "std", "internal_block")){
          let arg = mc.args.get(0).print();
          let id = i32::parse(arg.str()).unwrap();
          let blk: Block* = *resolver.block_map.get(&id).unwrap();
          self.visit_block(blk);
          arg.drop();
          return ptr::null<Value>();
        }
        if(Utils::is_call(mc, "std", "typeof")){
          let arg = mc.args.get(0);
          let ty = self.getType(arg);
          let str = ty.print();
          let ptr = self.get_alloc(expr);
          let res = self.str_lit(str.str(), ptr);
          str.drop();
          ty.drop();
          return res;
        }
        if(Utils::is_call(mc, "std", "no_drop")){
          let arg = mc.args.get(0);
          self.own.get().do_move(arg);
          return ptr::null<Value>();
        }
        let info = resolver.format_map.get(&expr.id);
        if(info.is_none()){
          resolver.err(expr, "internal err no macro");
        }
        let res = self.visit_block(&info.unwrap().block);
        if(res.is_some()) return res.unwrap();
        return ptr::null<Value>();
    }

    func visit_call(self, expr: Expr*, mc: Call*): Value*{
      let resolver = self.get_resolver();
      let env = std::getenv("ignore_drop");
      let ll = self.ll.get();
      //todo dont remove this until own is stable
      if(is_drop_call2(mc) && env.is_some()){
        let list = env.unwrap().split(",");
        //let cur_name: str = Path::name(self.unit().path.str());
        let cur_name: str = Path::name(self.curMethod.unwrap().path.str()); 
        if(list.contains(&cur_name)){
          //let arg = mc.scope.get();
          //self.own.get().do_move(arg);
          list.drop();
          return ptr::null<Value>();
        }
        list.drop();
      }
      if(Utils::is_call(mc, "std", "no_drop")){
        let arg = mc.args.get(0);
        self.own.get().do_move(arg);
        return ptr::null<Value>();
      }
      //////////////////////////////////////
      if(Utils::is_call(mc, "ptr", "deref")){
        let arg_ptr = self.get_obj_ptr(mc.args.get(0));
        let type = self.getType(expr);
        if (!is_struct(&type)) {
            let res = CreateLoad(ll.builder, self.mapType(&type), arg_ptr);
            type.drop();
            return res;
        }
        type.drop();
        return arg_ptr;
      }
      if(Utils::is_call(mc, "ptr", "get")){
        let elem_type = self.getType(expr);
        let src = self.get_obj_ptr(mc.args.get(0));
        let idx = self.loadPrim(mc.args.get(1));
        let res = self.ll.get().gep_ptr(self.mapType(elem_type.deref_ptr()), src, idx);
        elem_type.drop();
        return res;
      }
      if(Utils::is_call(mc, "ptr", "copy")){
        //ptr::copy(src_ptr, src_idx, elem)
        let src_ptr = self.get_obj_ptr(mc.args.get(0));
        let i64_ty = Type::new("i64");
        let idx = self.cast(mc.args.get(1), &i64_ty);
        i64_ty.drop();
        let val = self.visit(mc.args.get(2));
        let elem_type: Type = self.getType(mc.args.get(2));
        let trg_ptr = self.ll.get().gep_ptr(self.mapType(&elem_type), src_ptr, idx);
        self.copy(trg_ptr, val, &elem_type);
        elem_type.drop();
        return ptr::null<Value>();
      }
      if(Utils::is_call(mc, "std", "no_drop")){
        let arg = mc.args.get(0);
        self.own.get().do_move(arg);
        return ptr::null<Value>();
      }
      /// /////////////////////////////
      let mac = resolver.format_map.get(&expr.id);
      if(mac.is_some()){
        let res = self.visit_block(&mac.unwrap().block);
        if(res.is_some()){
          return res.unwrap();
        }
        return ptr::null<Value>();
      }
      if(Utils::is_call(mc, "std", "debug") || Utils::is_call(mc, "std", "debug2")){
        let info = resolver.format_map.get(&expr.id).unwrap();
        self.visit_block(&info.block);
        return ptr::null<Value>();
      }
      if(Utils::is_call(mc, "std", "print_type")){
        let info = resolver.format_map.get(&expr.id).unwrap();
        return self.visit_block(&info.block).unwrap();
      }
      if(Utils::is_call(mc, "Drop", "drop")){
        //print("drop_call {} line: {}\n", expr, expr.line);
        let argt = self.getType(mc.args.get(0));
        if(argt.is_any_pointer() || argt.is_prim()){
          argt.drop();
          return ptr::null<Value>();
        }
        let helper = DropHelper{resolver};
        if(!helper.is_drop_type(&argt)){
          argt.drop();
          return ptr::null<Value>();
        }
        argt.drop();
      }

      if(Utils::is_call(mc, "std", "size")){
        if(!mc.args.empty()){
          let ty = self.getType(mc.args.get(0));
          let sz = self.getSize(&ty) / 8;
          ty.drop();
          return ll.makeInt(sz, 32) ;
        }else{
          let ty = mc.type_args.get(0);
          let sz = self.getSize(ty) / 8;
          return ll.makeInt(sz, 32) ;
        }
      }    
      if(Utils::is_call(mc, "std", "is_ptr")){
        let ty = mc.type_args.get(0);
        if(ty.is_pointer()){
          return getTrue(ll.builder);
        }
        return getFalse(ll.builder);
      }
      if(Resolver::is_printf(mc)){
        self.call_printf(mc);
        return ptr::null<Value>();
      }
      if(Resolver::is_sprintf(mc)){
        return self.call_sprintf(mc);
      }
      if(Resolver::is_print(mc)){
        let info = resolver.format_map.get(&expr.id).unwrap();
        self.visit_block(&info.block);
        return ptr::null<Value>();
      }
      if(Resolver::is_panic(mc)){
        let info = resolver.format_map.get(&expr.id).unwrap();
        self.visit_block(&info.block);
        return ptr::null<Value>();
      }
      if(Resolver::is_format(mc)){
        let info = resolver.format_map.get(&expr.id).unwrap();
        let res = self.visit_block(&info.block);
        //self.own.get().do_move(info.block.return_expr.get());
        return res.unwrap();
      }
      if(Resolver::is_assert(mc)){
        let info = resolver.format_map.get(&expr.id).unwrap();
        self.visit_block(&info.block);
        return ptr::null<Value>();
      }
      if(mc.name.eq("malloc") && mc.scope.is_none()){
        let i64_ty = Type::new("i64");
        let size = self.cast(mc.args.get(0), &i64_ty);
        i64_ty.drop();
        if (!mc.type_args.empty()) {
            let typeSize = self.getSize(mc.type_args.get(0)) / 8;
            size = CreateNSWMul(ll.builder, size, ll.makeInt(typeSize, 64));
        }
        let proto = self.protos.get().libc("malloc");
        let args = [size];
        let res = CreateCall(ll.builder, proto.val, args.ptr(), 1);
        return res;
      }
      if(Utils::is_call(mc, "ptr", "null")){
        let ty = self.mapType(mc.type_args.get(0));
        return ConstantPointerNull_get(getPointerTo(ty));
      }
      if(resolver.is_array_get_len(mc)){
        let arr_type = self.getType(mc.scope.get());
        let arr_type2 = arr_type.deref_ptr();
        if let Type::Array(elem, sz)=arr_type2{
          arr_type.drop();
          return ll.makeInt(*sz, 64) ;
        }
        arr_type.drop();
        //std::unreachable!();
        panic("");
      }
      if(resolver.is_array_get_ptr(mc)){
        //arr.ptr()
        return self.get_obj_ptr(mc.scope.get());
      }
      if(resolver.is_slice_get_len(mc)){
        //sl.len()
        let sl = self.get_obj_ptr(mc.scope.get());
        let sliceType=self.protos.get().std("slice");
        let len_ptr = CreateStructGEP(ll.builder,  sliceType, sl,  SLICE_LEN_INDEX());
        return CreateLoad(ll.builder, intTy(ll.ctx, SLICE_LEN_BITS()), len_ptr);
      }
      if(resolver.is_slice_get_ptr(mc)){
        //sl.ptr()
        let sl = self.get_obj_ptr(mc.scope.get());
        let sliceType=self.protos.get().std("slice");
        let ptr = CreateStructGEP(ll.builder,  sliceType, sl,  SLICE_PTR_INDEX());
        return ll.loadPtr(ptr);
      }
      return self.visit_call2(expr, mc);
    }
    func visit_fp_call(self, expr: Expr*, mc: Call*, ft: FunctionType*): Value*{
      let ll = self.ll.get();
      let resolver = self.get_resolver();
      let val = self.visit_name(expr, &mc.name, false);
      val = ll.loadPtr(val);
      let proto = self.make_proto(ft);
      let args = List<Value*>::new();
      let paramIdx = 0;
      for arg in &mc.args{
        let at = resolver.getType(arg);
        if (at.is_any_pointer()) {
          args.add(self.get_obj_ptr(arg));
        }
        else if (is_struct(&at)) {
          let de = is_deref(arg);
          if (de.is_some()) {
            args.add(self.get_obj_ptr(de.unwrap()));
          }
          else {
            args.add(self.visit(arg));
          }
        } else {
            let pt0 = ft.params.get(paramIdx);
            let pt = resolver.visit_type(pt0).unwrap();
            args.add(self.cast(arg, &pt));
            pt.drop();
        }
        ++paramIdx;
        at.drop();
      }
      let res = CreateCall_ft(ll.builder, proto as llvm_FunctionType*, val, args.ptr(), args.len() as i32);
      args.drop();
      return res;
    }
    func visit_lambda_call(self, expr: Expr*, mc: Call*, rt: RType*): Value*{
      let ll = self.ll.get();
      let resolver = self.get_resolver();
      let val = self.visit_name(expr, &mc.name, false);
      val = ll.loadPtr(val);
      let ft0 = Option<LambdaType*>::none();
      if let Type::Lambda(bx) = &rt.lambda_call.get().type{
          ft0.set(bx.get());
      }else{
          panic("impossible");
          //Option<LambdaType>::none().get()
      }
      let ft = ft0.unwrap();
      let proto = self.make_proto(ft);
      let args = List<Value*>::new();
      let paramIdx = 0;
      for arg in &mc.args{
        let at = resolver.getType(arg);
        if (at.is_any_pointer()) {
          args.add(self.get_obj_ptr(arg));
        }
        else if (is_struct(&at)) {
          let de = is_deref(arg);
          if (de.is_some()) {
            args.add(self.get_obj_ptr(de.unwrap()));
          }
          else {
            args.add(self.visit(arg));
          }
        } else {
            let pt0 = ft.params.get(paramIdx);
            let pt = resolver.visit_type(pt0).unwrap();
            args.add(self.cast(arg, &pt));
            pt.drop();
        }
        ++paramIdx;
        at.drop();
      }
      let res = CreateCall_ft(ll.builder, proto as llvm_FunctionType*, val, args.ptr(), args.len() as i32);
      args.drop();
      return res;
    }
    func visit_call2(self, expr: Expr*, mc: Call*): Value*{
      let resolver = self.get_resolver();
      let ll = self.ll.get();
      let rt = resolver.visit(expr);
      if(rt.fp_info.is_some()){
        return self.visit_fp_call(expr, mc, rt.fp_info.get());
      }
      if(rt.lambda_call.is_some()){
        return self.visit_lambda_call(expr, mc, &rt);
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
      let ll = self.ll.get();
      if(is_struct(&rt.type)){
        self.own.get().add_obj(expr, LLVMPtr::new(ptr_ret.unwrap()), &rt.type);
      }
      let target: Method* = self.get_resolver().get_method(&rt).unwrap();
      self.cache.inc.depends_func(self.get_resolver(), target);
      rt.drop();
      let proto = self.protos.get().get_func(target);
      let args = List<Value*>::new();
      if(ptr_ret.is_some()){
        args.add(ptr_ret.unwrap());
      }
      let paramIdx = 0;
      let argIdx = 0;
      if(target.self.is_some()){
        let rval = RvalueHelper::need_alloc(mc, target, self.get_resolver());
        let scp_val = self.get_obj_ptr(*rval.scope.get());
        if(rval.rvalue){
          let rv_ptr = self.get_alloc(*rval.scope.get());
          CreateStore(ll.builder, scp_val, rv_ptr);
          args.add(rv_ptr);
        }else{
          args.add(scp_val);
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
          args.add(val);
        }
        else if (at.is_any_pointer()) {
          args.add(self.get_obj_ptr(arg));
        }
        else if (is_struct(&at)) {
          let de = is_deref(arg);
          if (de.is_some()) {
            args.add(self.get_obj_ptr(de.unwrap()));
          }
          else {
            args.add(self.visit(arg));
          }
        }
        else {
          if(target.is_vararg && paramIdx >= target.params.len()){
            args.add(self.loadPrim(arg));
          }else{
            let prm = target.params.get(paramIdx);
            let pt = self.get_resolver().getType(&prm.type);
            args.add(self.cast(arg, &pt));
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
      let res = CreateCall(ll.builder, proto.val, args.ptr(), args.len() as i32);
      args.drop();
      if(Resolver::is_exit(mc)){
        CreateUnreachable(ll.builder);
      }
      if(ptr_ret.is_some()) return ptr_ret.unwrap();
      return res;
    }
  
    func visit_print(self, mc: Call*): Value*{
      let ll = self.ll.get();
      let args = List<Value*>::new();
      for(let i = 0;i < mc.args.len();++i){
        let arg: Expr* = mc.args.get(i);
        let lit = is_str_lit(arg);
        if(lit.is_some()){
          let val: String = lit.unwrap().clone();
          let ptr = self.get_global_string(val);
          args.add(ptr);
          continue;
        }
        let arg_type = self.getType(arg);
        if(arg_type.eq("i8*") || arg_type.eq("u8*")){
          let val = self.get_obj_ptr(arg);
          args.add(val);
        }
        else if(arg_type.is_str()){
          panic("print str");
        }else if(arg_type.is_prim()){
          let val = self.loadPrim(arg);
          //val = CreateLoad(ll.builder, self.mapType(&arg_type), val);
          args.add(val);
        }else{
          panic("print {:?}", arg_type);
        }
        arg_type.drop();
      }
      //self.call_printf();
      let printf_proto = self.protos.get().libc("printf");
      let res = CreateCall(ll.builder, printf_proto.val, args.ptr(), args.len() as i32);
      args.drop();
      //flush
      self.emit_fflush();
      return res;
    }

    func emit_fflush(self){
      let ll = self.ll.get();
      let proto = self.protos.get().libc("fflush");
      let stdout_ptr = self.protos.get().stdout_ptr;
      let args = [ll.loadPtr(stdout_ptr)];
      CreateCall(ll.builder, proto.val, args.ptr(), 1);
    }
  
    func call_printf(self, mc: Call*){
      let ll = self.ll.get();
      let args = List<Value*>::new();
      for(let i = 0;i < mc.args.len();++i){
        let arg: Expr* = mc.args.get(i);
        let lit = is_str_lit(arg);
        if(lit.is_some()){
          let val: String = lit.unwrap().clone();
          let ptr = self.get_global_string(val);
          args.add(ptr);
          continue;
        }
        let arg_type = self.getType(arg);
        if(arg_type.eq("i8*") || arg_type.eq("u8*")){
          let val = self.get_obj_ptr(arg);
          args.add(val);
          arg_type.drop();
          continue;
        }
        if(arg_type.is_prim()){
          let val = self.loadPrim(arg);
          if(arg_type.eq("f32")){
            val = CreateFPExt(ll.builder, val, getDoubleTy(ll.ctx));
          }
          args.add(val);
        }else if(arg_type.is_any_pointer()){
          let val = self.get_obj_ptr(arg);
          args.add(val);
          arg_type.drop();
          continue;
        }else{
          panic("compiler err printf arg {:?}", arg_type);
        }
        arg_type.drop();
      }
      let proto = self.protos.get().libc("printf");
      let res = CreateCall(ll.builder, proto.val, args.ptr(), args.len() as i32);
      args.drop();
      //flush
      self.emit_fflush();
    }

    func call_sprintf(self, mc: Call*): Value*{
      let ll = self.ll.get();
      let args = List<Value*>::new();
      for(let i = 0;i < mc.args.len();++i){
        let arg: Expr* = mc.args.get(i);
        let lit: Option<String*> = is_str_lit(arg);
        if(lit.is_some()){
          let val: String = lit.unwrap().clone();
          let ptr = self.get_global_string(val);
          args.add(ptr);
          continue;
        }
        let arg_type = self.getType(arg);
        if(arg_type.eq("i8*") || arg_type.eq("u8*")){
          let val = self.get_obj_ptr(arg);
          args.add(val);
          arg_type.drop();
          continue;
        }
        if(arg_type.is_prim()){
          let val = self.loadPrim(arg);
          args.add(val);
        }else if(arg_type.is_any_pointer()){
          let val = self.get_obj_ptr(arg);
          args.add(val);
          arg_type.drop();
          continue;
        }else{
          panic("compiler err sprintf arg {:?}", arg_type);
        }
        arg_type.drop();
      }
      let proto = self.protos.get().libc("sprintf");
      let res = CreateCall(ll.builder, proto.val, args.ptr(), args.len() as i32);
      args.drop();
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
      match expr{
        Expr::Par(e)=>{
          return is_logic(e.get());
        },
        Expr::Infix(op, l, r)=>{
          if(op.eq("&&") || op.eq("||")){
            return true;
          }
          return false;
        },
        _=> return false,
      }
    }
  
    func andOr(self, op: String*, l: Expr*, r: Expr*): Pair<Value*, BasicBlock*>{
      let ll = self.ll.get();
      let isand = true;
      if(op.eq("||")) isand = false;
  
      let lval = self.branch(l);//must be eval first
      let bb = GetInsertBlock(ll.builder);
      let then = create_bb(ll.ctx, "".ptr(), self.cur_func());
      let next = create_bb(ll.ctx, "".ptr(), self.cur_func());
      if (isand) {
        CreateCondBr(ll.builder, lval, then, next);
      } else {
        CreateCondBr(ll.builder, lval, next, then);
      }
      SetInsertPoint(ll.builder, then);
      let rv = Option<Value*>::new();
      if(is_logic(r)){
        let r_inner = r;
        if let Expr::Par(e) = r{
          r_inner = e.get();
        }
        if let Expr::Infix(op2, l2, r2) = r_inner{
          let pair = self.andOr(op2, l2.get(), r2.get());
          then = pair.b;
          rv = Option::new(pair.a);
        }else{
          panic("");
        }
      }else{
        rv = Option::new(self.loadPrim(r));
      }
      let rbit = CreateZExt(ll.builder, rv.unwrap(), intTy(ll.ctx,8));
      CreateBr(ll.builder, next);
      SetInsertPoint(ll.builder, next);
      let phi = CreatePHI(ll.builder, intTy(ll.ctx, 8), 2);
      let i8val = 0;
      if(!isand){
        i8val = 1;
      }
      phi_addIncoming(phi, ll.makeInt(i8val, 8), bb);
      phi_addIncoming(phi, rbit, then);
      return Pair::new(CreateZExt(ll.builder, phi as Value* , intTy(ll.ctx, 8)), next);
    }
    
    func visit_lit(self, expr: Expr*, node: Literal*): Value*{
      let ll = self.ll.get();
      match &node.kind{
        LitKind::BOOL => {
          if(node.val.eq("true")) return getTrue(ll.builder);
          return getFalse(ll.builder);
        },
        LitKind::STR => {
          let trg_ptr = self.get_alloc(expr);
          return self.str_lit(node.val.str(), trg_ptr);
        },
        LitKind::CHAR => {
          assert(node.val.len() == 1);
          let chr: i8 = node.val.get(0);
          return ll.makeInt(chr, 32) ;
        },
        LitKind::FLOAT => {
          if(node.suffix.is_some()){
            if(node.suffix.get().eq("f64")){
              let valf: f64 = f64::parse(node.val.str());
              return ll.makeDouble(valf) ;
            }
          }
          let valf: f32 = f32::parse(node.val.str());
          return ll.makeFloat(valf) ;
        },
        LitKind::INT => {
          let bits = 32;
          if (node.suffix.is_some()) {
              bits = self.getSize(node.suffix.get()) as i32;
          }
          let trimmed = node.trim_suffix();
          let normal = trimmed.replace("_", "");
          let val: i64 = 0;
          if (normal.str().starts_with("0x") || normal.str().starts_with("-0x")){
            val = i64::parse_hex(normal.str()).unwrap();
          }else{
            val = i64::parse(normal.str()).unwrap();
          }
          normal.drop();
          return ll.makeInt(val, bits) ;
        },
      }
    }

    func str_lit(self, val: str, trg_ptr: Value*): Value*{
      let ll = self.ll.get();
      let src = self.get_global_string(val.str());
      let str_ty = Type::new("str");
      let stringType = self.mapType(&str_ty);
      let sliceType = self.protos.get().std("slice");
      let slice_ptr = CreateStructGEP(ll.builder, stringType, trg_ptr, 0);
      let data_target = CreateStructGEP(ll.builder, sliceType, slice_ptr, SLICE_PTR_INDEX());
      let len_target = CreateStructGEP(ll.builder, sliceType, slice_ptr, SLICE_LEN_INDEX());
      //set ptr
      CreateStore(ll.builder, src, data_target);
      //set len
      let len = ll.makeInt(val.len(), SLICE_LEN_BITS()) ;
      CreateStore(ll.builder, len, len_target);
      str_ty.drop();
      return trg_ptr;
    }
  
    func set_fields(self, ptr: Value*, decl: Decl*,ty: llvm_Type*, args: List<Entry>*, fields: List<FieldDecl>*){
      let ll = self.ll.get();
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
        let field_target_ptr = CreateStructGEP(ll.builder, ty, ptr, prm_idx);
        self.setField(&arg.expr, &fd.type, field_target_ptr);
        self.own.get().do_move(&arg.expr);
      }
    }
    func visit_obj(self, node: Expr*, type: Type*, args: List<Entry>*): Value*{
      let ptr = self.get_alloc(node);
      return self.visit_obj(node, type, args, ptr);
    }
    
    func visit_obj(self, node: Expr*, type: Type*, args: List<Entry>*, ptr: Value*): Value*{
        let ll = self.ll.get();
        let rt = self.get_resolver().visit(node);
        self.own.get().add_obj(node, LLVMPtr::new(ptr), &rt.type);
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
          let base_ptr = CreateStructGEP(ll.builder,  ty, ptr,  base_index);
          let val_ptr = self.visit(&arg.expr);
          let base_ty = self.get_resolver().getType(&arg.expr);
          self.copy(base_ptr, val_ptr, &base_ty);
          base_ty.drop();
          self.own.get().do_move(&arg.expr);
        }
        match decl{
          Decl::Struct(fields)=>{
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
              let field_target_ptr = CreateStructGEP(ll.builder,  ty, ptr,  prm_idx);
              self.setField(&arg.expr, &fd.type, field_target_ptr);
              self.own.get().do_move(&arg.expr);
            }
          },
          Decl::TupleStruct(fields)=>{
            panic("todo");
          },
          Decl::Enum(variants)=>{
            let variant_index = Resolver::findVariant(decl, type.name());
            let variant = decl.get_variants().get(variant_index);
            //set tag
            let tag_ptr = CreateStructGEP(ll.builder, ty, ptr, get_tag_index(decl));
            let tag_val = ll.makeInt(variant_index, ENUM_TAG_BITS()) ;
            CreateStore(ll.builder, tag_val, tag_ptr);
            //set data
            let data_ptr = CreateStructGEP(ll.builder, ty, ptr, get_data_index(decl));
            let var_ty = self.get_variant_ty(decl, variant);
            self.set_fields(data_ptr, decl, var_ty, args, &variant.fields);
          }
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
      let ll = self.ll.get();
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
          let tmp = CreateFAdd(ll.builder, lval, rv);
          CreateStore(ll.builder, tmp, lv);
          return lv;
        }
        let tmp = CreateNSWAdd(ll.builder, lval, rv);
        CreateStore(ll.builder, tmp, lv);
        return lv;
      }
      if(op.eq("-=")){
        let lv = self.visit(l);
        let lval = self.loadPrim(l);
        if(type.is_float()){
          let tmp = CreateFSub(ll.builder, lval, rv);
          CreateStore(ll.builder, tmp, lv);
          return lv;
        }
        let tmp = CreateNSWSub(ll.builder, lval, rv);
        CreateStore(ll.builder, tmp, lv);
        return lv;
      }
      if(op.eq("*=")){
        let lv = self.visit(l);
        let lval = self.loadPrim(l);
        if(type.is_float()){
          let tmp = CreateFMul(ll.builder, lval, rv);
          CreateStore(ll.builder, tmp, lv);
          return lv;
        }
        let tmp = CreateNSWMul(ll.builder, lval, rv);
        CreateStore(ll.builder, tmp, lv);
        return lv;
      }
      if(op.eq("/=")){
        let lv = self.visit(l);
        let lval = self.loadPrim(l);
        if(type.is_float()){
          let tmp = CreateFDiv(ll.builder, lval, rv);
          CreateStore(ll.builder, tmp, lv);
          return lv;
        }
        let tmp = CreateSDiv(ll.builder, lval, rv);
        CreateStore(ll.builder, tmp, lv);
        return lv;
      }
      let lv = self.cast(l, type);
      if(is_comp(op.str())){
        //todo remove redundant cast
        let op_c = op.clone().cstr();
        if(type.is_float()){
          let res = CreateCmp(ll.builder, get_comp_op_float(op_c.ptr()), lv, rv);
          op_c.drop();
          return res;
        }
        let res = CreateCmp(self.ll.get().builder, get_comp_op(op_c.ptr()), lv, rv) ;
        op_c.drop();
        return res;
      }
      if(op.eq("+")){
        if(type.is_float()){
          return CreateFAdd(ll.builder, lv, rv);
        }
        return CreateNSWAdd(ll.builder, lv, rv);
      }
      if(op.eq("-")){
        if(type.is_float()){
          return CreateFSub(ll.builder, lv, rv);
        }
        return CreateNSWSub(ll.builder, lv, rv);
      }
      if(op.eq("*")){
        if(type.is_float()){
          return CreateFMul(ll.builder, lv, rv);
        }
        return CreateNSWMul(ll.builder, lv, rv);
      }
      if(op.eq("/")){
        if(type.is_float()){
          return CreateFDiv(ll.builder, lv, rv);
        }
        return CreateSDiv(ll.builder, lv, rv);
      }
      if(op.eq("%")){
        if(type.is_float()){
          return CreateFRem(ll.builder, lv, rv);
        }
        return CreateSRem(ll.builder, lv, rv);
      }
      if(op.eq("&")){
        return CreateAnd(ll.builder, lv, rv);
      }
      if(op.eq("|")){
        return CreateOr(ll.builder, lv, rv);
      }
      if(op.eq("^")){
        return CreateXor(ll.builder, lv, rv);
      }
      if(op.eq("<<")){
        return CreateShl(ll.builder, lv, rv);
      }
      if(op.eq(">>")){
        return CreateAShr(ll.builder, lv, rv);
      }
      panic("infix '{}'\n", op);
    }
    
    func get_lhs(self, expr: Expr*): Value*{
      if let Expr::Unary(op, l2)=expr{
        if(op.eq("*")){
          let lhs = self.get_obj_ptr(l2.get());
          return lhs;
        }
      }
      if let Expr::Name(name)=expr{
        return self.visit_name(expr, name, false);
      }
      return self.visit(expr);
    }
  
    func visit_assign(self, l: Expr*, r: Expr*): Value*{
      if(l is Expr::Infix) panic("assign lhs");
      let type = self.getType(l);
      if let Expr::Unary(op,l2)=l{
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
      let ll = self.ll.get();
      let rt = self.get_resolver().visit(expr);
      match expr{
        Expr::Obj(obj_type, entries) => {
          self.visit_obj(expr, obj_type, entries, trg_ptr);
        },
        Expr::Lit(lit) => {
          if(lit.kind is LitKind::STR){
            self.str_lit(lit.val.str(), trg_ptr);
          }else{
            let val = self.visit_lit(expr, lit);
            CreateStore(ll.builder, val, trg_ptr);
          }
        },
        Expr::Call(mc) => {
          if(is_struct(&rt.type)){
            self.visit_call2(expr, mc, Option::new(trg_ptr), rt);
          }else{
            let val = self.visit_call2(expr, mc, Option<Value*>::new(), rt);
            CreateStore(ll.builder, val, trg_ptr);
          }
          return;//rt is moved,return
        },
        Expr::Array(list, size) => {
          if(!Compiler::is_constexpr(expr)){
            //AllocHelper::new(self).visit_child(expr);
            self.visit_array(expr, list, size, trg_ptr);
          }else{
            panic("glob rhs arr '{:?}'", expr);
          }
        },
        _ => {
          //todo slice
          panic("glob rhs '{:?}'", expr);
        },
      }
      rt.drop();
    }
}//end impl Compiler


func is_deref(expr: Expr*): Option<Expr*>{
  if let Expr::Unary(op, e) = expr{
      if(op.eq("*")) return Option::new(e.get());
  }
  return Option<Expr*>::new();
}