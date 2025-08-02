import std/map
import std/stack

import ast/ast
import ast/utils
import ast/printer

import resolver/resolver

import parser/compiler
import parser/expr_emitter
import parser/debug_helper
import parser/compiler_helper
import parser/ownership
import parser/own_model

//stmt
impl Compiler{
    func visit(self, node: Stmt*){
      self.di.get().loc(node.line, node.pos);
      match node{
        Stmt::Ret(e) => self.visit_ret(node, e),
        Stmt::Var(ve) => self.visit_var(ve),
        Stmt::Expr(e) => self.visit(e);,
        Stmt::For(fs) => self.visit_for(node, fs),
        Stmt::ForEach(fe) => self.visit_for_each(node, fe),
        Stmt::While(cnd, body) => self.visit_while(node, cnd, body.get()),
        Stmt::Continue => {
          self.own.get().do_continue(node.line);
          //CreateBr(self.loops.last().begin_bb);
          LLVMBuildBr(self.ll.get().builder, self.loops.last().begin_bb as LLVMOpaqueBasicBlock*);
        },
        Stmt::Break => {
          self.own.get().do_break(node.line);
          //CreateBr(self.loops.last().next_bb);
          LLVMBuildBr(self.ll.get().builder, self.loops.last().next_bb as LLVMOpaqueBasicBlock*);
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

    func visit_body(self, body: Body*): Option<LLVMOpaqueValue*>{
      match body{
        Body::Block(b) => return self.visit_block(b),
        Body::Stmt(s) => {
          self.visit(s);
          return Option<LLVMOpaqueValue*>::new();
        },
        Body::If(b) => return self.visit_if(b),
        Body::IfLet(b) => {
          return self.visit_iflet(b.rhs.line, b);
        },
      }
    }
    
    func visit_for_each(self, stmt: Stmt*, node: ForEach*){
      let info = self.get_resolver().format_map.get(&stmt.id).unwrap();
      //todo own doesnt move rhs
      self.visit_block(&info.block);
    }
    
    func visit_while(self, stmt: Stmt*, cond: Expr*, body: Body*){
      let line = stmt.line;
      let cond_name = CStr::new(format("while_cond_{}", line));
      let then_name = CStr::new(format("while_then_{}", line));
      let next_name = CStr::new(format("while_next_{}", line));
      let ll = self.ll.get();
      let then = LLVMAppendBasicBlockInContext(self.ll.get().ctx, self.cur_func(), then_name.ptr());
      let condbb = LLVMAppendBasicBlockInContext(self.ll.get().ctx, self.cur_func(), cond_name.ptr());
      let next = LLVMAppendBasicBlockInContext(self.ll.get().ctx, self.cur_func(), next_name.ptr());
      LLVMBuildBr(ll.builder, condbb);
      LLVMPositionBuilderAtEnd(ll.builder, condbb);
      LLVMBuildCondBr(ll.builder, self.branch(cond), then, next);
      LLVMPositionBuilderAtEnd(ll.builder, then);
      self.loops.add(LoopInfo{condbb, next});
      self.di.get().new_scope(body.line());
      self.own.get().add_scope(ScopeType::WHILE, body);
      self.visit_body(body);
      self.own.get().end_scope(get_end_line(body));
      self.di.get().exit_scope();
      self.loops.pop_back();
      let exit_body = Exit::get_exit_type(body);
      if(!exit_body.is_jump()){
          LLVMBuildBr(ll.builder, condbb);
      }
      LLVMPositionBuilderAtEnd(ll.builder, next);
      cond_name.drop();
      then_name.drop();
      next_name.drop();
    }
  
    func visit_for(self, stmt: Stmt*, node: ForStmt*){
      if(node.var_decl.is_some()){
        self.visit_var(node.var_decl.get());
      }
      let ll = self.ll.get();
      let f = self.cur_func();
      let line = stmt.line;
      let then_name = CStr::new(format("for_then_{}", line));
      let cond_name = CStr::new(format("for_cond_{}", line));
      let update_name = CStr::new(format("for_update_{}", line));
      let next_name = CStr::new(format("for_next_{}", line));
      let then = LLVMAppendBasicBlockInContext(self.ll.get().ctx, self.cur_func(), then_name.ptr());
      let condbb = LLVMAppendBasicBlockInContext(self.ll.get().ctx, self.cur_func(), cond_name.ptr());
      let updatebb = LLVMAppendBasicBlockInContext(self.ll.get().ctx, self.cur_func(), update_name.ptr());
      let next = LLVMAppendBasicBlockInContext(self.ll.get().ctx, self.cur_func(), next_name.ptr());
  
      LLVMBuildBr(ll.builder, condbb as LLVMOpaqueBasicBlock*);
      LLVMPositionBuilderAtEnd(ll.builder, condbb as LLVMOpaqueBasicBlock*);
      
      /*let di_scope =*/ self.di.get().new_scope(stmt.line);
      if (node.cond.is_some()) {
        LLVMBuildCondBr(ll.builder, self.branch(node.cond.get()), then as LLVMOpaqueBasicBlock*, next as LLVMOpaqueBasicBlock*);
      } else {
        LLVMBuildBr(ll.builder, then as LLVMOpaqueBasicBlock*);
      }
      LLVMPositionBuilderAtEnd(ll.builder, then as LLVMOpaqueBasicBlock*);
      self.loops.add(LoopInfo{updatebb, next});
      self.own.get().add_scope(ScopeType::FOR, node.body.get());
      self.visit_body(node.body.get());
      self.own.get().end_scope(get_end_line(node.body.get()));
      //self.di.get().exit_scope();
      let exit = Exit::get_exit_type(node.body.get());
      if(!exit.is_jump()){
        LLVMBuildBr(ll.builder, updatebb); 
      }
      LLVMPositionBuilderAtEnd(ll.builder, updatebb);
      //self.di.get().new_scope(di_scope);
      for (let i = 0;i < node.updaters.len();++i) {
        let u = node.updaters.get(i);
        self.visit(u);
      }
      self.di.get().exit_scope();
      self.loops.pop_back();
      LLVMBuildBr(ll.builder, condbb);
      LLVMPositionBuilderAtEnd(ll.builder, next);

      then_name.drop();
      cond_name.drop();
      update_name.drop();
      next_name.drop();
    }

    func visit_var(self, node: VarExpr*){
      let ll = self.ll.get();
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
          let tyy = LLVMTypeOf(val);
          if(/*Value_isPointerTy(val)*/ LLVMGetTypeKind(tyy) == LLVMTypeKind::LLVMPointerTypeKind{}.int()){
            self.copy(ptr, val, &type);
          }else{
            //CreateStore(val, ptr);
            LLVMBuildStore(ll.builder, val, ptr);
          }
        }else if(type.is_pointer() || type.is_fpointer() || type.is_lambda()){
          let val = self.get_obj_ptr(&f.rhs);
          //CreateStore(val, ptr);
          LLVMBuildStore(ll.builder, val, ptr);
        } else{
          let val = self.cast(&f.rhs, &type);
          LLVMBuildStore(ll.builder, val, ptr);
        }
        self.di.get().dbg_var(&f.name, &type, f.line, self);
        type.drop();
        self.own.get().add_var(f, ptr);
      }
    }

    func visit_block(self, node: Block*): Option<LLVMOpaqueValue*>{
      for(let i = 0;i < node.list.len();++i){
        let st = node.list.get(i);
        self.visit(st);
      }
      if(node.return_expr.is_some()){
        let val = self.visit(node.return_expr.get());
        let rt = self.get_resolver().visit(node.return_expr.get());
        if(is_loadable(&rt.type)){//todo remove
          val = self.loadPrim(val, &rt.type);
        }
        self.own.get().do_move(node.return_expr.get());
        rt.drop();
        return Option<LLVMOpaqueValue*>::new(val);
      }
      return Option<LLVMOpaqueValue*>::new();
    }

    func visit_ret(self, node: Stmt*, val: Option<Expr>*){
      let ll = self.ll.get();
      if(val.is_none()){
        self.own.get().do_return(node.line);
        self.exit_frame();
        if(is_main(self.curMethod.unwrap())){
          LLVMBuildRet(ll.builder, ll.makeInt(0, 32));
        }else{
          LLVMBuildRetVoid(ll.builder);
        }
      }else{
        self.visit_ret(val.get());
      }
    }

    func visit_ret(self, val: LLVMOpaqueValue*){
      let ll = self.ll.get();
      let mtype: Type* = &self.curMethod.unwrap().type;
      let type = self.get_resolver().getType(mtype);
      if(type.is_pointer() || type.is_fpointer()){
        self.exit_frame();
        //CreateRet(val);
        LLVMBuildRet(ll.builder, val);
        type.drop();
        return;
      }
      if(!is_struct(&type)){
        self.exit_frame();
        //CreateRet(val);
        LLVMBuildRet(ll.builder, val);
        type.drop();
        return;
      }
      let sret_ptr = LLVMGetParam(self.protos.get().cur.unwrap(), 0);
      self.copy(sret_ptr, val, &type);
      self.exit_frame();
      //CreateRetVoid();
      LLVMBuildRetVoid(ll.builder);
      type.drop();
    }

    func visit_ret(self, expr: Expr*){
      let ll = self.ll.get();
      let mtype: Type* = &self.curMethod.unwrap().type;
      let type = self.get_resolver().getType(mtype);
      if(type.is_pointer() || type.is_fpointer()){
        let val = self.get_obj_ptr(expr);
        self.own.get().do_return(expr);
        self.exit_frame();
        //CreateRet(val);
        LLVMBuildRet(ll.builder, val);
        type.drop();
        return;
      }
      if(!is_struct(&type)){
        let val = self.cast(expr, &type);
        self.own.get().do_return(expr);
        self.exit_frame();
        //CreateRet(val);
        LLVMBuildRet(ll.builder, val);
        type.drop();
        return;
      }
      let sret_ptr = LLVMGetParam(self.protos.get().cur.unwrap(), 0);
      if(can_inline(expr, self.get_resolver())){
        self.do_inline(expr, sret_ptr);
      }else{
        let val = self.visit(expr);
        self.copy(sret_ptr, val, &type);
      }
      self.own.get().do_return(expr);
      self.exit_frame();
      //CreateRetVoid();
      LLVMBuildRetVoid(ll.builder);
      type.drop();
    }
}//end impl
  