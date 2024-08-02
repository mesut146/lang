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
import std/map
import std/stack

//stmt
impl Compiler{
    func visit(self, node: Stmt*){
      self.llvm.di.get().loc(node.line, node.pos);
      if let Stmt::Ret(e*) = (node){
        if(e.is_none()){
          self.own.get().do_return(node.line);
          self.exit_frame();
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
        self.visit_var(ve);
      }
      else if let Stmt::Expr(e*)=(node){
        self.visit(e);
      }
      else if let Stmt::If(is*)=(node){
        self.visit_if(is);
      }
      else if let Stmt::IfLet(is*)=(node){
        self.visit_iflet(node, is);
      }
      else if let Stmt::Block(b*)=(node){
        self.visit_block(b);
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
        self.own.get().do_continue();
        CreateBr(*self.loops.last());
      }
      else if(node is Stmt::Break){
        self.own.get().do_break();
        CreateBr(*self.loopNext.last());
      }
      else{
        panic("visit {}", node);
      }
      return;
    }
    func get_end_line(stmt: Stmt*): i32{
      if let Stmt::Block(b*)=(stmt){
        return b.end_line;
      }
      return stmt.line;
    }
    
    func visit_while(self, stmt: Stmt*, cond: Expr*, body: Stmt*){
      let line = stmt.line;
      let cond_name = CStr::new(format("while_cond_{}", line));
      let then_name = CStr::new(format("while_then_{}", line));
      let next_name = CStr::new(format("while_next_{}", line));
      let then = create_bb_named(then_name.ptr());
      let condbb = create_bb2_named(self.cur_func(), cond_name.ptr());
      let next = create_bb_named(next_name.ptr());
      cond_name.drop();then_name.drop();next_name.drop();
      CreateBr(condbb);
      SetInsertPoint(condbb);
      CreateCondBr(self.branch(cond), then, next);
      self.set_and_insert(then);
      self.loops.add(condbb);
      self.loopNext.add(next);
      self.llvm.di.get().new_scope(body.line);
      self.own.get().add_scope(ScopeType::WHILE, body);
      self.visit(body);
      self.own.get().end_scope(get_end_line(body));
      self.llvm.di.get().exit_scope();
      self.loops.pop_back();
      self.loopNext.pop_back();
      CreateBr(condbb);
      self.set_and_insert(next);
    }

    func visit_if(self, node: IfStmt*){
      let cond = self.branch(&node.cond);
      let line = node.cond.line;
      let then_name = CStr::new(format("if_then_{}", line));
      let else_name = CStr::new(format("if_else_{}", line));
      let next_name = CStr::new(format("if_next_{}", line));
      let then = create_bb_named(then_name.ptr());
      let elsebb = create_bb_named(else_name.ptr());
      let next = create_bb_named(next_name.ptr());
      then_name.drop();else_name.drop();next_name.drop();
      CreateCondBr(cond, then, elsebb);
      self.set_and_insert(then);
      self.llvm.di.get().new_scope(node.then.get().line);
      let exit_then = Exit::get_exit_type(node.then.get());
      let if_id = self.own.get().add_scope(ScopeType::IF, node.then.get());
      self.visit(node.then.get());
      //else move aware end_scope
      if(node.else_stmt.is_some()){
        self.own.get().end_scope_if(&node.else_stmt, get_end_line(node.then.get()));
      }else{
        self.own.get().end_scope(get_end_line(node.then.get()));
      }
      self.llvm.di.get().exit_scope();
      if(!exit_then.is_jump()){
        CreateBr(next);
      }
      self.set_and_insert(elsebb);
      let else_jump = false;
      if(node.else_stmt.is_some()){
        self.llvm.di.get().new_scope(node.else_stmt.get().line);
        //this will restore if, bc we did fake end_scope
        let else_id = self.own.get().add_scope(ScopeType::ELSE, node.else_stmt.get());
        self.own.get().get_scope(else_id).sibling = if_id;
        self.visit(node.else_stmt.get());
        self.own.get().end_scope(get_end_line(node.else_stmt.get()));
        self.llvm.di.get().exit_scope();
        let exit_else = Exit::get_exit_type(node.else_stmt.get());
        else_jump = exit_else.is_jump();
        if(!else_jump){
          CreateBr(next);
        }
        exit_else.drop();
      }else{
        let else_id = self.own.get().add_scope(ScopeType::ELSE, line, Exit::new(ExitType::NONE));
        self.own.get().get_scope(else_id).sibling = if_id;
        self.own.get().end_scope(get_end_line(node.then.get()));
        CreateBr(next);
      }
      if(!(exit_then.is_jump() && else_jump)){
        SetInsertPoint(next);
        self.add_bb(next);
      }
      exit_then.drop();
    }
  
    func visit_iflet(self, stmt: Stmt*, node: IfLet*){
      let rt = self.get_resolver().visit_type(&node.type);
      let decl = self.get_resolver().get_decl(&rt).unwrap();
      rt.drop();
      let rhs = self.get_obj_ptr(&node.rhs);
      let tag_ptr = self.gep2(rhs, get_tag_index(decl), self.mapType(&decl.type));
      let tag = CreateLoad(getInt(ENUM_TAG_BITS()), tag_ptr);
      let index = Resolver::findVariant(decl, node.type.name());
      let cmp = CreateCmp(get_comp_op("==".ptr()), tag, makeInt(index, ENUM_TAG_BITS()));
  
      let then_name = CStr::new(format("iflet_then_{}", stmt.line));
      let else_name = CStr::new(format("iflet_else_{}", stmt.line));
      let next_name = CStr::new(format("iflet_next_{}", stmt.line));
      let then_bb = create_bb2_named(self.cur_func(), then_name.ptr());
      let elsebb = create_bb_named(else_name.ptr());
      let next = create_bb_named(next_name.ptr());
      then_name.drop();else_name.drop();next_name.drop();
      CreateCondBr(self.branch(cmp), then_bb, elsebb);
      SetInsertPoint(then_bb);
      let if_id = self.own.get().add_scope(ScopeType::IF, node.then.get());
      self.own.get().do_move(&node.rhs);
      let variant = decl.get_variants().get_ptr(index);
      self.llvm.di.get().new_scope(stmt.line);
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
                      rt2.drop();
                      self.get_resolver().err(&node.rhs, "can't deref member from ptr rhs");
                    }else{
                      rt2.drop();
                    }
                    self.copy(alloc_ptr, field_ptr, &prm.type);
                    self.own.get().add_iflet_var(arg, prm, alloc_ptr);
                }
                self.llvm.di.get().dbg_var(&arg.name, &prm.type, arg.line, self);
            }
        }
      }
      self.visit(node.then.get());
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
      if (node.else_stmt.is_some()) {
        self.llvm.di.get().new_scope(node.else_stmt.get().line);
        let else_id = self.own.get().add_scope(ScopeType::ELSE, node.else_stmt.get());
        self.own.get().get_scope(else_id).sibling = if_id;
        self.visit(node.else_stmt.get());
        self.own.get().end_scope(get_end_line(node.else_stmt.get()));
        self.llvm.di.get().exit_scope();
        let exit_else = Exit::get_exit_type(node.else_stmt.get());
        else_jump = exit_else.is_jump();
        if (!else_jump) {
          CreateBr(next);
        }
        exit_else.drop();
      }else{
        let else_id = self.own.get().add_scope(ScopeType::ELSE, stmt.line, Exit::new(ExitType::NONE));
        self.own.get().get_scope(else_id).sibling = if_id;
        self.own.get().end_scope(get_end_line(node.then.get()));
        CreateBr(next);
      }
      if(!(exit_then.is_jump() && else_jump)){
        SetInsertPoint(next);
        self.add_bb(next);
      }
      exit_then.drop();
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

      then_name.drop();cond_name.drop();update_name.drop();next_name.drop();
  
      CreateBr(condbb);
      SetInsertPoint(condbb);
      
      let di_scope = self.llvm.di.get().new_scope(stmt.line);
      if (node.cond.is_some()) {
        CreateCondBr(self.branch(node.cond.get()), then, next);
      } else {
        CreateBr(then);
      }
      self.llvm.di.get().exit_scope();
      self.set_and_insert(then);
      self.loops.add(updatebb);
      self.loopNext.add(next);
      self.llvm.di.get().new_scope(node.body.get().line);
      self.own.get().add_scope(ScopeType::FOR, node.body.get());
      self.visit(node.body.get());
      self.own.get().end_scope(get_end_line(node.body.get()));
      self.llvm.di.get().exit_scope();
      CreateBr(updatebb);
      SetInsertPoint(updatebb);
      self.llvm.di.get().new_scope(di_scope);
      for (let i = 0;i < node.updaters.len();++i) {
        let u = node.updaters.get_ptr(i);
        self.visit(u);
      }
      self.llvm.di.get().exit_scope();
      self.loops.pop_back();
      self.loopNext.pop_back();
      CreateBr(condbb);
      self.set_and_insert(next);
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
    func visit_block(self, node: Block*){
      for(let i = 0;i < node.list.len();++i){
        let st = node.list.get_ptr(i);
        self.visit(st);
      }
    }
    func visit_ret(self, expr: Expr*){
      let mtype = &self.curMethod.unwrap().type;
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
  