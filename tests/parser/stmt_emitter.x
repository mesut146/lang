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
          self.own.get().do_return();
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
      else if let Stmt::While(cnd*, body*)=(node){
        self.visit_while(node, cnd, body);
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
    
    func visit_while(self, stmt: Stmt*, cond: Expr*, body: Block*){
      let line = stmt.line;
      let cond_name = format("while_cond_{}", line);
      let then_name = format("while_then_{}", line);
      let next_name = format("while_next_{}", line);
      let then = create_bb_named(CStr::new(then_name).ptr());
      let condbb = create_bb2_named(self.cur_func(), CStr::new(cond_name).ptr());
      let next = create_bb_named(CStr::new(next_name).ptr());
      CreateBr(condbb);
      SetInsertPoint(condbb);
      CreateCondBr(self.branch(cond), then, next);
      self.set_and_insert(then);
      self.loops.add(condbb);
      self.loopNext.add(next);
      self.llvm.di.get().new_scope(body.line);
      self.own.get().add_scope(ScopeType::WHILE, body);
      self.visit_block(body);
      self.own.get().end_scope();
      self.llvm.di.get().exit_scope();
      self.loops.pop_back();
      self.loopNext.pop_back();
      CreateBr(condbb);
      self.set_and_insert(next);
    }

    func visit_if(self, node: IfStmt*){
      let cond = self.branch(&node.e);
      let line = node.e.line;
      let then_name = format("if_then_{}", line);
      let else_name = format("if_else_{}", line);
      let next_name = format("if_next_{}", line);
      let then = create_bb_named(CStr::new(then_name).ptr());
      let elsebb = create_bb_named(CStr::new(else_name).ptr());
      let next = create_bb_named(CStr::new(next_name).ptr());
      CreateCondBr(cond, then, elsebb);
      self.set_and_insert(then);
      self.llvm.di.get().new_scope(node.then.get().line);
      let exit_then = Exit::get_exit_type(node.then.get());
      self.own.get().add_scope(ScopeType::IF, node.then.get());
      self.visit(node.then.get());
      //dont drop anything, we need else moves too
      let own_if = self.own.get().end_if_scope();
      self.llvm.di.get().exit_scope();
      if(!exit_then.is_jump()){
        CreateBr(next);
      }
      self.set_and_insert(elsebb);
      let else_jump = false;
      if(node.els.is_some()){
        self.llvm.di.get().new_scope(node.els.get().get().line);
        //this will restore if, bc we did fake end_scope
        self.own.get().add_scope(ScopeType::ELSE, node.els.get().get());
        self.visit(node.els.get().get());
        self.own.get().end_scope();
        self.llvm.di.get().exit_scope();
        let exit_else = Exit::get_exit_type(node.els.get().get());
        else_jump = exit_else.is_jump();
        if(!else_jump){
          CreateBr(next);
        }
        exit_else.drop();
      }else{
        CreateBr(next);
      }
      if(!(exit_then.is_jump() && else_jump)){
        SetInsertPoint(next);
        self.add_bb(next);
      }
      exit_then.drop();
    }
  
    func visit_iflet(self, stmt: Stmt*, node: IfLet*){
      let rt = self.get_resolver().visit_type(&node.ty);
      let decl = self.get_resolver().get_decl(&rt).unwrap();
      let rhs = self.get_obj_ptr(&node.rhs);
      let tag_ptr = self.gep2(rhs, get_tag_index(decl), self.mapType(&decl.type));
      let tag = CreateLoad(getInt(ENUM_TAG_BITS()), tag_ptr);
      let index = Resolver::findVariant(decl, node.ty.name());
      let cmp = CreateCmp(get_comp_op("==".cstr().ptr()), tag, makeInt(index, ENUM_TAG_BITS()));
  
      let then_name = format("iflet_then_{}", stmt.line);
      let else_name = format("iflet_else_{}", stmt.line);
      let next_name = format("iflet_next_{}", stmt.line);
      let then_bb = create_bb2_named(self.cur_func(), CStr::new(then_name).ptr());
      let elsebb = create_bb_named(CStr::new(else_name).ptr());
      let next = create_bb_named(CStr::new(next_name).ptr());
      CreateCondBr(self.branch(cmp), then_bb, elsebb);
      SetInsertPoint(then_bb);
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
            //self.own.get().add_iflet_var(arg, prm);
            let real_idx = i;
            if(decl.base.is_some()){
              ++real_idx;
            }
            let field_ptr = self.gep2(dataPtr, real_idx, var_ty);
            let alloc_ptr = self.get_alloc(arg.id);
            self.NamedValues.add(arg.name.clone(), alloc_ptr);
            if (arg.is_ptr) {
                CreateStore(field_ptr, alloc_ptr);
                let ty_ptr = prm.type.clone().toPtr();
                self.llvm.di.get().dbg_var(&arg.name, &ty_ptr, arg.line, self);
            } else {
                if (prm.type.is_prim() || prm.type.is_pointer()) {
                    let field_val = CreateLoad(self.mapType(&prm.type), field_ptr);
                    CreateStore(field_val, alloc_ptr);
                } else {
                    self.copy(alloc_ptr, field_ptr, &prm.type);
                }
                self.llvm.di.get().dbg_var(&arg.name, &prm.type, arg.line, self);
            }
        }
      }
      self.visit(node.then.get());
      self.llvm.di.get().exit_scope();
      let exit_then = Exit::get_exit_type(node.then.get());
      if (!exit_then.is_jump()) {
        CreateBr(next);
      }
      self.set_and_insert(elsebb);
      let else_jump = false;
      if (node.els.is_some()) {
        self.llvm.di.get().new_scope(node.els.get().get().line);
        self.visit(node.els.get().get());
        self.llvm.di.get().exit_scope();
        let exit_else = Exit::get_exit_type(node.els.get().get());
        else_jump = exit_else.is_jump();
        if (!else_jump) {
          CreateBr(next);
        }
        exit_else.drop();
      }else{
        CreateBr(next);
      }
      if(!(exit_then.is_jump() && else_jump)){
        SetInsertPoint(next);
        self.add_bb(next);
      }
      exit_then.drop();
    }
  
    func visit_for(self, stmt: Stmt*, node: ForStmt*){
      if(node.v.is_some()){
        self.visit_var(node.v.get());
      }
      let f = self.cur_func();
      let line = stmt.line;
      let then_name = format("for_then_{}", line);
      let cond_name = format("for_cond_{}", line);
      let update_name = format("for_update_{}", line);
      let next_name = format("for_next_{}", line);
      let then = create_bb_named(CStr::new(then_name).ptr());
      let condbb = create_bb2_named(f, CStr::new(cond_name).ptr());
      let updatebb = create_bb2_named(f, CStr::new(update_name).ptr());
      let next = create_bb_named(CStr::new(next_name).ptr());
  
      CreateBr(condbb);
      SetInsertPoint(condbb);
      
      let di_scope = self.llvm.di.get().new_scope(stmt.line);
      if (node.e.is_some()) {
        CreateCondBr(self.branch(node.e.get()), then, next);
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
      self.own.get().end_scope();
      self.llvm.di.get().exit_scope();
      CreateBr(updatebb);
      SetInsertPoint(updatebb);
      self.llvm.di.get().new_scope(di_scope);
      for (let i = 0;i < node.u.len();++i) {
        let u = node.u.get_ptr(i);
        self.visit(u);
      }
      self.llvm.di.get().exit_scope();
      self.loops.pop_back();
      self.loopNext.pop_back();
      CreateBr(condbb);
      self.set_and_insert(next);
    }

    func visit_assert(self, expr: Expr*){
      let m = self.curMethod.unwrap();
      let msg = format("{}:{} in {}\nassertion {} failed\n", m.path, expr.line, m.name, expr).cstr();
      let ptr = CreateGlobalStringPtr(msg.ptr());
      Drop::drop(msg);
      let then_name = format("assert_then_{}", expr.line);
      let next_name = format("assert_next_{}", expr.line);
      let then = create_bb2_named(self.cur_func(), CStr::new(then_name).ptr());
      let next = create_bb_named(CStr::new(next_name).ptr());
      let cond = self.branch(expr);
      CreateCondBr(cond, next, then);
      SetInsertPoint(then);
      //print error and exit
      let pr_args = make_args();
      args_push(pr_args, ptr);
      let printf_proto = self.protos.get().libc("printf");
      CreateCall(printf_proto, pr_args);
      //self.call_exit(1);
      self.set_and_insert(next);
    }

    func visit_var(self, node: VarExpr*){
      for(let i = 0;i < node.list.len();++i){
        let f = node.list.get_ptr(i);
        let ptr = self.get_alloc(f.id);
        self.NamedValues.add(f.name.clone(), ptr);
        let type = self.get_resolver().getType(f);
        if(doesAlloc(&f.rhs, self.get_resolver())){
          //self allocated
          self.visit(&f.rhs);
          self.llvm.di.get().dbg_var(&f.name, &type, f.line, self);
          self.own.get().add_var(f);
          continue;
        }
        if(is_struct(&type)){
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
        self.own.get().add_var(f);
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
        CreateRet(val);
        return;
      }
      if(!is_struct(&type)){
        let val = self.cast(expr, &type);
        self.own.get().do_return(expr);
        CreateRet(val);
        return;
      }
      let ptr = get_arg(self.protos.get().cur.unwrap(), 0) as Value*;
      let val = self.visit(expr);
      self.copy(ptr, val, &type);
      self.own.get().do_return(expr);
      CreateRetVoid();
    }
}//end impl
  