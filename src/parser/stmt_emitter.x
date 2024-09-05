import parser/compiler
import parser/expr_emitter
import parser/resolver
import parser/ast
import parser/bridge
import parser/debug_helper
import parser/compiler_helper
import parser/utils
import parser/printer
import parser/ownership
import parser/own_model
import std/map
import std/stack

//stmt
impl Compiler{
    func visit(self, node: Stmt*){
      self.llvm.di.get().loc(node.line, node.pos);
      if let Stmt::Ret(e*) = (node){
        self.visit_ret(node, e);
      }
      else if let Stmt::Var(ve*)=(node){
        self.visit_var(ve);
      }
      else if let Stmt::Expr(e*)=(node){
        self.visit(e);
      }
      else if let Stmt::For(fs*)=(node){
        self.visit_for(node, fs);
      }
      else if let Stmt::ForEach(fe*)=(node){
        self.visit_for_each(node, fe);
      }
      else if let Stmt::While(cnd*, body*)=(node){
        self.visit_while(node, cnd, body.get());
      }
      else if(node is Stmt::Continue){
        self.own.get().do_continue(node.line);
        CreateBr(*self.loops.last());
      }
      else if(node is Stmt::Break){
        self.own.get().do_break(node.line);
        CreateBr(*self.loopNext.last());
      }
      else{
        panic("visit {}", node);
      }
      return;
    }
    func get_end_line(stmt: Stmt*): i32{
      /*if let Stmt::Block(b*)=(stmt){
        return b.end_line;
      }*/
      return stmt.line;
    }

    func get_end_line(body: Body*): i32{
      if let Body::Block(b*)=(body){
        return b.end_line;
      }else if let Body::Stmt(b*)=(body){
        return b.line;
      }else if let Body::If(b*)=(body){
        return b.cond.line;
      }else if let Body::IfLet(b*)=(body){
        return b.rhs.line;
      }else{
        panic("");
      }
    }

    func visit_body(self, body: Body*): Option<Value*>{
      if let Body::Block(b*)=(body){
        return self.visit_block(b);
      }else if let Body::Stmt(b*)=(body){
        self.visit(b);
        return Option<Value*>::new();
      }else if let Body::If(b*)=(body){
        return self.visit_if(b);
      }else if let Body::IfLet(b*)=(body){
        return self.visit_iflet(b.rhs.line, b);
      }
      panic("");
    }
    
    func visit_while(self, stmt: Stmt*, cond: Expr*, body: Body*){
      let line = stmt.line;
      let cond_name = CStr::new(format("while_cond_{}", line));
      let then_name = CStr::new(format("while_then_{}", line));
      let next_name = CStr::new(format("while_next_{}", line));
      let then = create_bb_named(then_name.ptr());
      let condbb = create_bb2_named(self.cur_func(), cond_name.ptr());
      let next = create_bb_named(next_name.ptr());
      CreateBr(condbb);
      SetInsertPoint(condbb);
      CreateCondBr(self.branch(cond), then, next);
      self.set_and_insert(then);
      self.loops.add(condbb);
      self.loopNext.add(next);
      self.llvm.di.get().new_scope(body.line());
      self.own.get().add_scope(ScopeType::WHILE, body);
      self.visit_body(body);
      self.own.get().end_scope(get_end_line(body));
      self.llvm.di.get().exit_scope();
      self.loops.pop_back();
      self.loopNext.pop_back();
      CreateBr(condbb);
      self.set_and_insert(next);
      cond_name.drop();
      then_name.drop();
      next_name.drop();
    }

    func is_nested_if(body: Body*): bool{
      if(body is Body::If || body is Body::IfLet) return true;
      if let Body::Block(blk*) = (body){
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
      let cond = self.branch(&node.cond);
      let line = node.cond.line;
      let then_name = CStr::new(format("if_then_{}", line));
      let else_name = CStr::new(format("if_else_{}", line));
      let next_name = CStr::new(format("if_next_{}", line));
      let thenbb = create_bb_named(then_name.ptr());
      let elsebb = create_bb_named(else_name.ptr());
      let nextbb = create_bb_named(next_name.ptr());
      CreateCondBr(cond, thenbb, elsebb);
      self.set_and_insert(thenbb);
      self.llvm.di.get().new_scope(node.then.get().line());
      let exit_then = Exit::get_exit_type(node.then.get());
      let if_id = self.own.get().add_scope(ScopeType::IF, node.then.get());
      let then_val = self.visit_body(node.then.get());
      let then_end = GetInsertBlock();
      let else_end = GetInsertBlock();
      //else move aware end_scope
      if(node.else_stmt.is_some()){
        self.own.get().end_scope_if(&node.else_stmt, get_end_line(node.then.get()));
      }else{
        self.own.get().end_scope(get_end_line(node.then.get()));
      }
      self.llvm.di.get().exit_scope();
      if(!exit_then.is_jump()){
        CreateBr(nextbb);
      }
      self.set_and_insert(elsebb);
      let else_jump = false;
      let else_val = Option<Value*>::new();
      
      if(node.else_stmt.is_some()){
        self.llvm.di.get().new_scope(node.else_stmt.get().line());
        //this will restore if, bc we did fake end_scope
        let else_id = self.own.get().add_scope(ScopeType::ELSE, node.else_stmt.get());
        self.own.get().get_scope(else_id).sibling = if_id;
        else_val = self.visit_body(node.else_stmt.get());
        else_end = GetInsertBlock();
        self.own.get().end_scope(get_end_line(node.else_stmt.get()));
        self.llvm.di.get().exit_scope();
        let exit_else = Exit::get_exit_type(node.else_stmt.get());
        else_jump = exit_else.is_jump();
        if(!else_jump){
          CreateBr(nextbb);
        }
        exit_else.drop();
      }else{
        let else_id = self.own.get().add_scope(ScopeType::ELSE, line, Exit::new(ExitType::NONE), true);
        self.own.get().get_scope(else_id).sibling = if_id;
        self.own.get().end_scope(get_end_line(node.then.get()));
        CreateBr(nextbb);
      }
      let res = Option<Value*>::new();
      if(!(exit_then.is_jump() && else_jump)){
        SetInsertPoint(nextbb);
        self.add_bb(nextbb);
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
            let phi = CreatePHI(phi_type, 2);
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
      }
      exit_then.drop();
      then_name.drop();
      else_name.drop();
      next_name.drop();
      return res;
    }
  
    func visit_iflet(self, line: i32, node: IfLet*): Option<Value*>{
      let rt = self.get_resolver().visit_type(&node.type);
      let decl = self.get_resolver().get_decl(&rt).unwrap();
      let rhs = self.get_obj_ptr(&node.rhs);
      let tag_ptr = self.gep2(rhs, get_tag_index(decl), self.mapType(&decl.type));
      let tag = CreateLoad(getInt(ENUM_TAG_BITS()), tag_ptr);
      let index = Resolver::findVariant(decl, node.type.name());
      let cmp = CreateCmp(get_comp_op("==".ptr()), tag, makeInt(index, ENUM_TAG_BITS()));
  
      let then_name = CStr::new(format("iflet_then_{}", line));
      let else_name = CStr::new(format("iflet_else_{}", line));
      let next_name = CStr::new(format("iflet_next_{}", line));
      let then_bb = create_bb2_named(self.cur_func(), then_name.ptr());
      let elsebb = create_bb_named(else_name.ptr());
      let next = create_bb_named(next_name.ptr());
      
      CreateCondBr(self.branch(cmp), then_bb, elsebb);
      SetInsertPoint(then_bb);
      let if_id = self.own.get().add_scope(ScopeType::IF, node.then.get());
      self.own.get().do_move(&node.rhs);
      let variant = decl.get_variants().get_ptr(index);
      self.llvm.di.get().new_scope(line);
      if(!variant.fields.empty()){
        //declare vars
        let fields = &variant.fields;
        let data_index = get_data_index(decl);
        let dataPtr = self.gep2(rhs, data_index, self.mapType(&decl.type));
        let var_ty = self.get_variant_ty(decl, variant);
        for (let i = 0; i < fields.size(); ++i) {
            //regular var decl
            let prm = fields.get_ptr(i);
            let arg = node.args.get_ptr(i);
            let gep_idx = i;
            if(decl.base.is_some()){
              ++gep_idx;
            }
            let field_ptr = self.gep2(dataPtr, gep_idx, var_ty);
            let alloc_ptr = self.get_alloc(arg.id);
            self.NamedValues.add(arg.name.clone(), alloc_ptr);
            if (arg.is_ptr) {
                CreateStore(field_ptr, alloc_ptr);
                let ty_ptr = prm.type.clone().toPtr();
                self.llvm.di.get().dbg_var(&arg.name, &ty_ptr, arg.line, self);
                ty_ptr.drop();
            } else {
                //deref
                if (prm.type.is_prim() || prm.type.is_pointer()) {
                    let field_val = CreateLoad(self.mapType(&prm.type), field_ptr);
                    CreateStore(field_val, alloc_ptr);
                } else {
                    //DropHelper::new(self.get_resolver()).is_drop_type(&node.rhs), delete this after below works
                    let rt2 = self.get_resolver().visit(&node.rhs);
                    if(rt2.type.is_pointer() && !prm.type.is_str()){
                      self.get_resolver().err(&node.rhs, "can't deref member from ptr rhs");
                    }
                    self.copy(alloc_ptr, field_ptr, &prm.type);
                    self.own.get().add_iflet_var(arg, prm, alloc_ptr);
                    rt2.drop();
                }
                self.llvm.di.get().dbg_var(&arg.name, &prm.type, arg.line, self);
            }
        }
      }
      let then_val = self.visit_body(node.then.get());
      let then_end = GetInsertBlock();
      let else_end = GetInsertBlock();
      //else move aware end_scope
      if(node.else_stmt.is_some()){
        self.own.get().end_scope_if(&node.else_stmt, get_end_line(node.then.get()));
      }else{
        self.own.get().end_scope(get_end_line(node.then.get()));
      }
      self.llvm.di.get().exit_scope();
      let exit_then = Exit::get_exit_type(node.then.get());
      if (!exit_then.is_jump()) {
        CreateBr(next);
      }
      self.set_and_insert(elsebb);
      let else_jump = false;
      let else_val = Option<Value*>::new();
      if (node.else_stmt.is_some()) {
        self.llvm.di.get().new_scope(node.else_stmt.get().line());
        let else_id = self.own.get().add_scope(ScopeType::ELSE, node.else_stmt.get());
        self.own.get().get_scope(else_id).sibling = if_id;
        else_val = self.visit_body(node.else_stmt.get());
        else_end = GetInsertBlock();
        self.own.get().end_scope(get_end_line(node.else_stmt.get()));
        self.llvm.di.get().exit_scope();
        let exit_else = Exit::get_exit_type(node.else_stmt.get());
        else_jump = exit_else.is_jump();
        if (!else_jump) {
          CreateBr(next);
        }
        exit_else.drop();
      }else{
        let else_id = self.own.get().add_scope(ScopeType::ELSE, line, Exit::new(ExitType::NONE), true);
        self.own.get().get_scope(else_id).sibling = if_id;
        self.own.get().end_scope(get_end_line(node.then.get()));
        CreateBr(next);
      }
      let res = Option<Value*>::new();
      if(!(exit_then.is_jump() && else_jump)){
        SetInsertPoint(next);
        self.add_bb(next);

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
            let phi = CreatePHI(phi_type, 2);
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
      }
      exit_then.drop();
      then_name.drop();
      else_name.drop();
      next_name.drop();
      rt.drop();
      return res;
    }

    func visit_for_each(self, stmt: Stmt*, node: ForEach*){
      let info = self.get_resolver().format_map.get_ptr(&stmt.id).unwrap();
      //todo own doesnt move rhs
      self.visit_block(&info.block);
    }
  
    func visit_for(self, stmt: Stmt*, node: ForStmt*){
      if(node.var_decl.is_some()){
        self.visit_var(node.var_decl.get());
      }
      let f = self.cur_func();
      let line = stmt.line;
      let then_name = CStr::new(format("for_then_{}", line));
      let cond_name = CStr::new(format("for_cond_{}", line));
      let update_name = CStr::new(format("for_update_{}", line));
      let next_name = CStr::new(format("for_next_{}", line));
      let then = create_bb_named(then_name.ptr());
      let condbb = create_bb2_named(f, cond_name.ptr());
      let updatebb = create_bb2_named(f, update_name.ptr());
      let next = create_bb_named(next_name.ptr());
  
      CreateBr(condbb);
      SetInsertPoint(condbb);
      
      /*let di_scope =*/ self.llvm.di.get().new_scope(stmt.line);
      if (node.cond.is_some()) {
        CreateCondBr(self.branch(node.cond.get()), then, next);
      } else {
        CreateBr(then);
      }
      //self.llvm.di.get().exit_scope();
      self.set_and_insert(then);
      self.loops.add(updatebb);
      self.loopNext.add(next);
      //self.llvm.di.get().new_scope(node.body.get().line);
      self.own.get().add_scope(ScopeType::FOR, node.body.get());
      self.visit_body(node.body.get());
      self.own.get().end_scope(get_end_line(node.body.get()));
      //self.llvm.di.get().exit_scope();
      CreateBr(updatebb);
      SetInsertPoint(updatebb);
      //self.llvm.di.get().new_scope(di_scope);
      for (let i = 0;i < node.updaters.len();++i) {
        let u = node.updaters.get_ptr(i);
        self.visit(u);
      }
      self.llvm.di.get().exit_scope();
      self.loops.pop_back();
      self.loopNext.pop_back();
      CreateBr(condbb);
      self.set_and_insert(next);

      then_name.drop();
      cond_name.drop();
      update_name.drop();
      next_name.drop();
    }

    func visit_var(self, node: VarExpr*){
      for(let i = 0;i < node.list.len();++i){
        let f = node.list.get_ptr(i);
        let ptr = self.get_alloc(f.id);
        self.NamedValues.add(f.name.clone(), ptr);
        let type = self.get_resolver().getType(f);
        if(can_inline(&f.rhs, self.get_resolver())){
          self.do_inline(&f.rhs, ptr);
        }
        else if(is_struct(&type)){
          let val = self.visit(&f.rhs);
          if(Value_isPointerTy(val)){
            self.copy(ptr, val, &type);
          }else{
            CreateStore(val, ptr);
          }
        }else if(type.is_pointer()){
          let val = self.get_obj_ptr(&f.rhs);
          CreateStore(val, ptr);
        } else{
          let val = self.cast(&f.rhs, &type);
          CreateStore(val, ptr);
        }
        self.llvm.di.get().dbg_var(&f.name, &type, f.line, self);
        type.drop();
        self.own.get().add_var(f, ptr);
      }
    }

    func visit_block(self, node: Block*): Option<Value*>{
      for(let i = 0;i < node.list.len();++i){
        let st = node.list.get_ptr(i);
        self.visit(st);
      }
      if(node.return_expr.is_some()){
        let val = self.visit(node.return_expr.get());
        let rt = self.get_resolver().visit(node.return_expr.get());
        if(is_loadable(&rt.type)){
          val = self.loadPrim(val, &rt.type);
        }
        rt.drop();
        return Option<Value*>::new(val);
      }
      return Option<Value*>::new();
    }

    func visit_ret(self, node: Stmt*, val: Option<Expr>*){
      if(val.is_none()){
        self.own.get().do_return(node.line);
        self.exit_frame();
        if(is_main(self.curMethod.unwrap())){
          CreateRet(makeInt(0, 32));
        }else{
          CreateRetVoid();
        }
      }else{
        self.visit_ret(val.get());
      }
    }

    func visit_ret(self, val: Value*){
      let mtype: Type* = &self.curMethod.unwrap().type;
      let type = self.get_resolver().getType(mtype);
      if(type.is_pointer()){
        self.exit_frame();
        CreateRet(val);
        type.drop();
        return;
      }
      if(!is_struct(&type)){
        self.exit_frame();
        CreateRet(val);
        type.drop();
        return;
      }
      let sret_ptr = get_arg(self.protos.get().cur.unwrap(), 0) as Value*;
      self.copy(sret_ptr, val, &type);
      self.exit_frame();
      CreateRetVoid();
      type.drop();
    }

    func visit_ret(self, expr: Expr*){
      let mtype: Type* = &self.curMethod.unwrap().type;
      let type = self.get_resolver().getType(mtype);
      if(type.is_pointer()){
        let val = self.get_obj_ptr(expr);
        self.own.get().do_return(expr);
        self.exit_frame();
        CreateRet(val);
        type.drop();
        return;
      }
      if(!is_struct(&type)){
        let val = self.cast(expr, &type);
        self.own.get().do_return(expr);
        self.exit_frame();
        CreateRet(val);
        type.drop();
        return;
      }
      let sret_ptr = get_arg(self.protos.get().cur.unwrap(), 0) as Value*;
      if(can_inline(expr, self.get_resolver())){
        self.do_inline(expr, sret_ptr);
      }else{
        let val = self.visit(expr);
        self.copy(sret_ptr, val, &type);
      }
      self.own.get().do_return(expr);
      self.exit_frame();
      CreateRetVoid();
      type.drop();
    }
}//end impl
  