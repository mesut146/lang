import std/map
import std/stack
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

//stmt
impl Compiler{
    func visit(self, node: Stmt*){
      self.llvm.di.get().loc(node.line, node.pos);
      match node{
        Stmt::Ret(e) => self.visit_ret(node, e),
        Stmt::Var(ve) => self.visit_var(ve),
        Stmt::Expr(e) => {
          self.visit(e);
          return;
        },
        Stmt::For(fs) => self.visit_for(node, fs),
        Stmt::ForEach(fe) => self.visit_for_each(node, fe),
        Stmt::While(cnd, body) => self.visit_while(node, cnd, body.get()),
        Stmt::Continue => {
          self.own.get().do_continue(node.line);
          CreateBr(self.loops.last().begin_bb);
        },
        Stmt::Break => {
          self.own.get().do_break(node.line);
          CreateBr(self.loops.last().next_bb);
        },
      }
    }
    func get_end_line(stmt: Stmt*): i32{
      if let Stmt::Expr(e) = stmt{
        return get_end_line(e);
      }
      return stmt.line;
    }

    func get_end_line(expr: Expr*): i32{
      match expr{
        Expr::If(is) => {
          return is.get().cond.line;
        },
        Expr::Match(ms) => {
          return ms.get().expr.line;
        },
        Expr::Block(block) => {
          return block.get().end_line;
        },
        _ => return expr.line,
      }
    }

    func get_end_line(body: Body*): i32{
      match body{
        Body::Block(b) => return b.end_line,
        Body::Stmt(s) => return s.line,
        Body::If(b) => return b.cond.line,
        Body::IfLet(b) => return b.rhs.line,
      }
    }
    func get_end_line(rhs: MatchRhs*): i32{
      match rhs{
        MatchRhs::STMT(stmt) => return get_end_line(stmt),
        MatchRhs::EXPR(expr) => return get_end_line(expr),
      }
    }

    func visit_body(self, body: Body*): Option<Value*>{
      match body{
        Body::Block(b) => return self.visit_block(b),
        Body::Stmt(s) => {
          self.visit(s);
          return Option<Value*>::new();
        },
        Body::If(b) => return self.visit_if(b),
        Body::IfLet(b) => {
          return self.visit_iflet(b.rhs.line, b);
        },
      }
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
      self.loops.add(LoopInfo{condbb, next});
      self.llvm.di.get().new_scope(body.line());
      self.own.get().add_scope(ScopeType::WHILE, body);
      self.visit_body(body);
      self.own.get().end_scope(get_end_line(body));
      self.llvm.di.get().exit_scope();
      self.loops.pop_back();
      let exit_body = Exit::get_exit_type(body);
      if(!exit_body.is_jump()){
          CreateBr(condbb);
      }
      self.set_and_insert(next);
      cond_name.drop();
      then_name.drop();
      next_name.drop();
    }

    func visit_for_each(self, stmt: Stmt*, node: ForEach*){
      let info = self.get_resolver().format_map.get(&stmt.id).unwrap();
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
      self.loops.add(LoopInfo{updatebb, next});
      //self.llvm.di.get().new_scope(node.body.get().line);
      self.own.get().add_scope(ScopeType::FOR, node.body.get());
      self.visit_body(node.body.get());
      self.own.get().end_scope(get_end_line(node.body.get()));
      //self.llvm.di.get().exit_scope();
      let exit = Exit::get_exit_type(node.body.get());
      if(!exit.is_jump()){
        CreateBr(updatebb);
      }
      SetInsertPoint(updatebb);
      //self.llvm.di.get().new_scope(di_scope);
      for (let i = 0;i < node.updaters.len();++i) {
        let u = node.updaters.get(i);
        self.visit(u);
      }
      self.llvm.di.get().exit_scope();
      self.loops.pop_back();
      CreateBr(condbb);
      self.set_and_insert(next);

      then_name.drop();
      cond_name.drop();
      update_name.drop();
      next_name.drop();
    }

    func visit_var(self, node: VarExpr*){
      for(let i = 0;i < node.list.len();++i){
        let f = node.list.get(i);
        let ptr = self.get_alloc(f.id);
        self.NamedValues.add(f.name.clone(), ptr);
        let type = self.get_resolver().getType(f);
        self.cache.inc.depends_decl(self.get_resolver(), &type);
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
        }else if(type.is_pointer() || type.is_fpointer() || type.is_lambda()){
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
        let st = node.list.get(i);
        self.visit(st);
      }
      if(node.return_expr.is_some()){
        let val = self.visit(node.return_expr.get());
        let rt = self.get_resolver().visit(node.return_expr.get());
        if(is_loadable(&rt.type)){
          val = self.loadPrim(val, &rt.type);
        }
        self.own.get().do_move(node.return_expr.get());
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
          CreateRet(makeInt(0, 32) as Value*);
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
      if(type.is_pointer() || type.is_fpointer()){
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
      if(type.is_pointer() || type.is_fpointer()){
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
  