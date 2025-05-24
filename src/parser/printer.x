
import parser/ast
import parser/parser
import parser/token
import std/fs
import std/result

static print_cst = false;
//static pretty_print = true;

func format_dir(dir: str, out: str){
    File::create_dir(out);
    let files = File::read_dir(dir).unwrap();
    for file in &files{
        let file2 = format("{}/{}", dir, file);
        let outf = format("{}/{}", out, file);
        if(File::is_dir(file2.str())) continue;
        print("file={}\n", file2);
        print("out={}\n", outf);
        let p = Parser::from_path(file2);
        let unit = p.parse_unit();
        let str = Fmt::str(&unit);
        File::write_string(str.str(), outf.str())?;
        outf.drop();
        str.drop();
    }
    files.drop();
}

//T: Debug
func join<T>(f: Fmt*, arr: List<T>*, sep: str){
  for(let i = 0;i < arr.len();++i){
    if(i > 0) f.print(sep);
    arr.get(i).debug(f);
  }
}

func body(node: Stmt*, f: Fmt*){
    body(node, f, false);
}

func body(node: Stmt*, f: Fmt*, skip_first: bool){
  let str = Fmt::str(node); 
  let lines: List<str> = str.split("\n");
  for(let j = 0;j < lines.len();++j){
    if(j > 0){
        f.print("\n");
    }
    if(j > 0 || !skip_first){
      f.print("    ");
    }
    f.print(lines.get(j));
  }
  str.drop();
  lines.drop();
}

func body(node: Expr*, f: Fmt*){
    body(node, f, false);
}

func body(node: Expr*, f: Fmt*, skip_first: bool){
  let str = Fmt::str(node); 
  let lines: List<str> = str.split("\n");
  for(let j = 0;j < lines.len();++j){
    if(j > 0 || !skip_first){
      f.print("    ");
    }
    f.print(lines.get(j));
    if(j < lines.len() - 1){
        f.print("\n");
    }
  }
  str.drop();
  lines.drop();
}
func body(str: String, f: Fmt*){
    for(let i=0;i<str.len();++i){
        let ch = str.get(i);
        if(ch=='\n'){
        }
        //f.print(ch);
    }
    str.drop();
}

impl Debug for QPath{
  func debug(self, f: Fmt*){
    join(f, &self.list, "::");
  }
}

impl Debug for Unit{
  func debug(self, f: Fmt*){
    join(f, &self.imports, "\n");
    if(!self.imports.empty()){
        f.print("\n\n");
    }
    join(f, &self.items, "\n\n");
  }
}


impl Debug for ImportStmt{
  func debug(self, f: Fmt*){
    f.print("import ");
    join(f, &self.list, "/");
  }
}

impl Debug for Item{
  func debug(self, f: Fmt*){
    match self{
      Item::Decl(decl) => {
        if(print_cst) f.print("Item::Decl{\n");
        decl.debug(f);
        if(print_cst) f.print("}");
      },
      Item::Method(m) => {
        m.debug(f);
      },
      Item::Impl(i) => {
        i.debug(f);
      },
      Item::Type(name, rhs) => {
        f.print("type ");
        f.print(name.str());
        f.print(" = ");
        rhs.debug(f);
        f.print(";");
      },
      Item::Trait(tr) => {
        f.print("trait ");
        tr.type.debug(f);
      },
      Item::Extern(methods) => {
        f.print("extern{\n");
        join(f, methods, "\n");
        f.print("\n}");
      },
      Item::Const(cn) => {
        f.print("const ");
        f.print(&cn.name);
        if(cn.type.is_some()){
          f.print(": ");
          cn.type.get().debug(f);
        }
        f.print(" = ");
        f.print(&cn.rhs);
      },
      Item::Glob(gl) => {
        gl.debug(f);
      },
      Item::Module(md) => {
        Debug::debug(md, f);
      },
      Item::Use(uit) => {
        Debug::debug(uit, f);
      }
    }
  }
}
impl Debug for UseItem{
  func debug(self, f: Fmt*){
    f.print("use ");
    join(f, &self.path, "::");
    if(self.has_multiple){
      f.print("::{");
      join(f, &self.list, ",");
      f.print("}");
    }else{
      f.print("::");
      Debug::debug(self.list.get(0), f);
    }
    f.print(";");
  }
}

impl Debug for Module{
  func debug(self, f: Fmt*){
    f.print("mod ");
    Debug::debug(&self.name, f);
    f.print("{\n");
    join(f, &self.items, "    \n");
    f.print("\n}");
  }
}

impl Debug for Global{
  func debug(self, f: Fmt*){
    f.print("static ");
    f.print(self.name.str());
    if(self.type.is_some()){
      f.print(": ");
      self.type.get().debug(f);
    }
    f.print(" = ");
    self.expr.debug(f);
    f.print(";");
  }
}

impl Debug for Impl{
  func debug(self, f: Fmt*){
    self.info.debug(f);
    f.print("{\n");
    for(let i=0;i<self.methods.len();++i){
        if(i>0){
            f.print("\n");
        }
      let ms = Fmt::str(self.methods.get(i));
      let lines = ms.str().split("\n");
      for(let j = 0;j < lines.len();++j){
        f.print("    ");
        f.print(lines.get(j));
        f.print("\n");
      }
      ms.drop();
      lines.drop();
    }
    f.print("\n}");
  }
}

impl Debug for ImplInfo{
  func debug(self, f: Fmt*){
    f.print("impl");
    if(!self.type_params.empty()){
      f.print("<");
      join(f, &self.type_params, ",");
      f.print(">");
    }
    f.print(" ");
    if(self.trait_name.is_some()){
      self.trait_name.get().debug(f);
      f.print(" for ");
    }
    self.type.debug(f);
  }
}

impl Debug for Decl{
    func debug(self, f: Fmt*){
      match self{
        Decl::Struct(fields) => {
            debug_struct(self, fields, f);
        },
        Decl::Enum(variants) => {
            debug_enum(self, variants, f);
        },
        Decl::TupleStruct(fields) => {
          debug_struct_tuple(self, fields, f);
        }
      }
    }
    func debug_struct(decl: Decl*, fields: List<FieldDecl>*, f: Fmt*){
        f.print("struct ");
        decl.type.debug(f);
        if(decl.base.is_some()){
          f.print(": ");
          decl.base.get().debug(f);
        }
        if(fields.empty()){
            f.print(";");
            return;
        }
        f.print("{\n");
        for(let i = 0;i < fields.len();++i){
          f.print("    ");
          fields.get(i).debug(f);
          f.print(";\n");
        }
        f.print("}");
    }

    func debug_struct_tuple(decl: Decl*, fields: List<FieldDecl>*, f: Fmt*){
      f.print("struct ");
      decl.type.debug(f);
      if(decl.base.is_some()){
        f.print(": ");
        decl.base.get().debug(f);
      }
      if(fields.empty()){
          f.print(";");
          return;
      }
      f.print("(\n");
      for(let i = 0;i < fields.len();++i){
        if(i > 0){
          f.print(", ");
        }
        fields.get(i).type.debug(f);
      }
      f.print(")");
  }


  func debug_enum(decl: Decl*, variants: List<Variant>*, f: Fmt*){
      f.print("enum ");
      decl.type.debug(f);
      f.print("{\n");
      for(let i = 0;i < variants.len();++i){
        let ev = variants.get(i);
        f.print("    ");
        f.print(&ev.name);
        if(ev.fields.len() > 0){
          //todo ev.is_tuple
          f.print("(");
          for(let j = 0;j < ev.fields.len();++j){
            if(j > 0) f.print(", ");
            ev.fields.get(j).debug(f);
          }
          f.print(")");
        }
        if(i < variants.len() - 1) f.print(",");
        f.print("\n");
      }
      f.print("}");
  }
}

impl Debug for FieldDecl{
  func debug(self, f: Fmt*){
    if(self.name.is_some()){
      f.print(self.name.get());
      f.print(": ");
    }
    self.type.debug(f);
    //f.print(";\n");
  }
}

impl Debug for Method{
  func debug(self, f: Fmt*){
    f.print("func ");
    f.print(&self.name);
    f.print("(");
    if(self.self.is_some()){
      self.self.get().debug(f);
      if(!self.params.empty()){
        f.print(", ");
      }
    }
    join(f, &self.params, ", ");
    if(self.is_vararg){
      if(!self.params.empty()){
        f.print(", ");
      }
      f.print("...");
    }
    f.print(")");
    if(!self.type.is_void()){
        f.print(": ");
        self.type.debug(f);
    }
    if(self.body.is_some()){
      self.body.get().debug(f);
    }else{
      f.print(";");
    }
  }
}

impl Debug for Param{
  func debug(self, f: Fmt*){
    if(self.is_deref){
      f.print("*");
    }
    f.print(&self.name);
    if(self.is_self){}
    f.print(": ");
    self.type.debug(f);
  }
}

impl Debug for Type{
  func debug(self, f: Fmt*){
      match self{
        Type::Simple(smp) => smp.debug(f),
        Type::Pointer(ty) => {
          ty.get().debug(f);
          f.print("*");
        },
        Type::Array(box, sz) => {
          f.print("[");
          box.get().debug(f);
          f.print("; ");
          sz.debug(f);
          f.print("]");
        },
        Type::Slice(box) => {
          f.print("[");
          box.get().debug(f);
          f.print("]");
        },
        Type::Function(ft) => {
          ft.get().debug(f);
        },
        Type::Lambda(lt) =>{
          lt.get().debug(f);
        },
        Type::Tuple(tt) => {
          f.print("(");
          join(f, &tt.types, ", ");
          f.print(")");
        }
    }
  }
}
impl Debug for Simple{
  func debug(self, f: Fmt*){
    if(self.scope.is_some()){
      self.scope.get().debug(f);
      f.print("::");
    }
    f.print(&self.name);
    if(!self.args.empty()){
      f.print("<");
      for(let i = 0;i < self.args.len();++i){
        if(i>0) f.print(", ");
        self.args.get(i).debug(f);
      }
      f.print(">");
    }
  }
}

impl Debug for FunctionType{
  func debug(self, f: Fmt*){
    f.print("func(");
    if(!self.params.empty()){
      join(f, &self.params, ", ");
    }
    f.print(") => ");
    self.return_type.debug(f);
  }
}

impl Debug for LambdaType{
  func debug(self, f: Fmt*){
    f.print("func2(");
    if(!self.params.empty()){
      join(f, &self.params, ", ");
    }
    f.print(")");
    if(self.return_type.is_some()){
        f.print(" => ");
        self.return_type.get().debug(f);
    }
  }
}

//statements------------------------------------------------
impl Debug for Stmt{
  func debug(self, f: Fmt*){
    match self{
      Stmt::Var(ve)=>{
        f.print("let ");
        ve.debug(f);
        f.print(";");
      },
      Stmt::Expr(e) => {
        if(print_cst) f.print("Stmt::Expr{\n");
        e.debug(f);
        if(!e.is_body()){
          f.print(";");
        }
        if(print_cst) f.print("}\n");
      },
      Stmt::Ret(e) =>{
        f.print("return");
        if(e.is_some()){
          f.print(" ");
          e.get().debug(f);
        }
        f.print(";");
      },
      Stmt::While(e, b)=>{
        f.print("while(");
        e.debug(f);
        f.print(")");
        b.get().debug(f);
      },
      Stmt::For(fs)=>{
        f.print("for(");
        if(fs.var_decl.is_some()){
          fs.var_decl.get().debug(f);
        }
        f.print(";");
        if(fs.cond.is_some()){
          fs.cond.get().debug(f);
        }
        f.print(";");
        join(f, &fs.updaters, ", ");
        f.print(")");
        fs.body.get().debug(f);
      },
      Stmt::Continue =>{
        f.print("continue;");
      },
      Stmt::Break =>{
        f.print("break;");
      },
      Stmt::ForEach(fe) => {
        f.print("for ");
        f.print(&fe.var_name);
        f.print(" in ");
        fe.rhs.debug(f);
        fe.body.debug(f);
      }
    }
  }
}

impl Debug for Body{
  func debug(self, f: Fmt*){
    match self{
      Body::Block(b)=>{
        if(print_cst) f.print("Body::Block{\n");
        b.debug(f);
        if(print_cst) f.print("}\n");
      },
      Body::Stmt(b)=>{
        if(print_cst) f.print("Body::Stmt{\n");
        b.debug(f);
        if(print_cst) f.print("}\n");
      },
      Body::If(b)=>{
        if(print_cst) f.print("Body::If{\n");
        b.debug(f);
        if(print_cst) f.print("}\n");
      },
      Body::IfLet(b)=>{
        if(print_cst) f.print("Body::IfLet{\n");
        b.debug(f);
        if(print_cst) f.print("}\n");
      }
    }
  }
}

impl Debug for ArgBind{
  func debug(self, f: Fmt*){
    f.print(&self.name);
    // if(self.is_ptr){
    //   f.print("*");
    // }
  }
}

impl Debug for Block{
  func debug(self, f: Fmt*){
    f.print("{\n");
    for(let i = 0;i < self.list.len();++i){
        if(i>0) f.print("\n");
       body(self.list.get(i), f);
    }
    if(self.return_expr.is_some()){
        if(!self.list.empty()){
            f.print("\n");
        }
      if(print_cst) f.print("Block::return_expr{\n");
      body(self.return_expr.get(), f);
      //self.return_expr.get().debug(f);
      //f.print("\n");
      if(print_cst) f.print("}\n");
    }
    f.print("\n}");
  }
}

impl Debug for VarExpr{
  func debug(self, f: Fmt*){
    for(let i=0;i<self.list.len();++i){
      self.list.get(i).debug(f);
    }
  }
}

impl Debug for Fragment{
  func debug(self, f: Fmt*){
    f.print(&self.name);
    if(self.type.is_some()){
      f.print(": ");
      self.type.get().debug(f);
    }
    f.print(" = ");
    self.rhs.debug(f);
  }
}

impl Debug for Literal{
  func debug(self, f: Fmt*){
    let replaced = self.val.replace("\n", "\\n");
    let tmp = replaced.replace("\"", "\\\"");
    replaced.drop();
    replaced = tmp;
    if(self.kind is LitKind::STR){
      f.print("\"");
    }else if(self.kind is LitKind::CHAR){
      f.print("'");
    }
    f.print(&replaced);
    if(self.kind is LitKind::STR){
      f.print("\"");
    }else if(self.kind is LitKind::CHAR){
      f.print("'");
    }
    /*if(self.suffix.is_some()){
      f.print("_");
      self.suffix.get().debug(f);
    }*/
    replaced.drop();
  }
}

//expr---------------------------------
impl Debug for Expr{
  func debug(self, f: Fmt*){
    match self{
      Expr::Lit(lit) => {
        if(print_cst) f.print("Expr::Lit{");
        lit.debug(f);
      },
      Expr::Name(v) => {
        if(print_cst) f.print("Expr::Lit{");
        f.print(v.str());
      },
      Expr::Call(call) => {
        if(print_cst) f.print("Expr::Call{");
        call.debug(f);
      },
      Expr::Par(e) => {
        if(print_cst) f.print("Expr::Par{");
        f.print("(");
        e.get().debug(f);
        f.print(")");
      },
      Expr::Tuple(elems) => {
        if(print_cst) f.print("Expr::Tuple{");
        f.print("(");
        join(f, elems, ",");
        f.print(")");
      },
      Expr::Type(t) => {
        if(print_cst) f.print("Expr::Type{");
        t.debug(f);
      },
      Expr::Unary(op, e) => {
        if(print_cst) f.print("Expr::Unary{");
        f.print(op);
        e.get().debug(f);
      },
      Expr::Infix(op, l, r) => {
        if(print_cst) f.print("Expr::Infix{");
        l.get().debug(f);
        f.print(" ");
        f.print(op);
        f.print(" ");
        r.get().debug(f);
      },
      Expr::Access(scp, nm) => {
        if(print_cst) f.print("Expr::Access{");
        scp.get().debug(f);
        f.print(".");
        f.print(nm);
      },
      Expr::Obj(ty, args) => {
        if(print_cst) f.print("Expr::Obj{");
        ty.debug(f);
        f.print("{");
        join(f, args, ", ");
        f.print("}");
      },
      Expr::As(e, type) => {
        if(print_cst) f.print("Expr::As{");
        e.get().debug(f);
        f.print(" as ");
        type.debug(f);
      },
      Expr::Is(e, rhs) => {
        if(print_cst) f.print("Expr::Is{");
        e.get().debug(f);
        f.print(" is ");
        rhs.get().debug(f);
      },
      Expr::Array(arr, sz) => {
        if(print_cst) f.print("Expr::Array{");
        f.print("[");
        join(f, arr, ", ");
        if(sz.is_some()){
          f.print("; ");
          sz.get().debug(f);
        }
        f.print("]");
      },
      Expr::ArrAccess(aa) => {
        if(print_cst) f.print("Expr::ArrAccess{");
        aa.arr.get().debug(f);
        f.print("[");
        aa.idx.get().debug(f);
        if(aa.idx2.is_some()){
          f.print("..");
          aa.idx2.get().debug(f);
        }
        f.print("]");
      },
      Expr::Block(b) => {
        if(print_cst) f.print("Expr::Block{");
        b.get().debug(f);
      },
      Expr::If(ife) => {
        if(print_cst) f.print("Expr::If{");
        ife.get().debug(f);
      },
      Expr::IfLet(il) => {
        if(print_cst) f.print("Expr::IfLet{");
        il.get().debug(f);
      },
      Expr::Match(me) => {
        if(print_cst) f.print("Expr::Match{");
        me.get().debug(f);
      },
      Expr::MacroCall(mc) => {
        Debug::debug(mc, f); 
      },
      Expr::Lambda(lc) => {
          f.print("|");
          f.print("|");
          if(lc.return_type.is_some()){
              f.print(": ");
              f.print(lc.return_type.get());
          }
          match (lc.body.get()){
              LambdaBody::Expr(e)=>{
                  body(e, f, true);
              },
              LambdaBody::Stmt(s)=>{
                  body(s, f, true);
              }
          }
      },
      Expr::Ques(bx) => {
        if(print_cst) f.print("Expr::Ques{");
        Debug::debug(bx.get(), f);
        f.print("?");
      }
    }
    if(print_cst) f.print("}");
  }
}
impl Debug for MatchLhs{
  func debug(self, f: Fmt*){
    match self{
      MatchLhs::NONE => f.print("_"),
      MatchLhs::ENUM(type, args) => {
        type.debug(f);
        if(!args.empty()){
          f.print("(");
          join(f, args, ", ");
          f.print(")");
        }
      },
      MatchLhs::UNION(types) => {
        join(f, types, " | ");
      }
    }
  }
}
impl Debug for Match{
  func debug(self, f: Fmt*){
    f.print("match ");
    self.expr.debug(f);
    f.print("{\n");
    for(let i = 0;i < self.cases.len();++i){
      if(i > 0){
        //f.print("    ,\n");
      }
      f.print("    ");
      let case = self.cases.get(i);
      Debug::debug(&case.lhs, f);
      f.print(" => ");
      match &case.rhs{
        MatchRhs::EXPR(expr)=>{
          //expr.debug(f);
          body(expr, f, true);
        },
        MatchRhs::STMT(stmt)=>{
          body(stmt, f, true);
          //stmt.debug(f);
        }
      }
      if(i < self.cases.len() - 1){
          f.print(",\n");
      }
    }
    f.print("\n}\n");
  } 
}

impl Debug for IfStmt{
  func debug(self, f: Fmt*){
    f.print("if(");
    self.cond.debug(f);
    f.print(")");
    if(!(self.then.get() is Body::Block)){
      f.print(" ");
    }
    self.then.get().debug(f);
    if(self.else_stmt.is_some()){
      f.print("\nelse ");
      let els = self.else_stmt.get();
      els.debug(f);
    }
  }
}

impl Debug for IfLet{
  func debug(self, f: Fmt*){
    f.print("if let ");
    self.type.debug(f);
    f.print("(");
    join(f, &self.args, ", ");
    f.print(") = ");
    self.rhs.debug(f);
    self.then.get().debug(f);
    if(self.else_stmt.is_some()){
      f.print("else ");
      self.else_stmt.get().debug(f);
    }
  }
}

impl Debug for MacroCall{
  func debug(self, f: Fmt*){
    if(self.scope.is_some()){
      Debug::debug(self.scope.get(), f);
      f.print("::");
    }
    f.print(&self.name);
    f.print("!(");
    join(f, &self.args, ", ");
    f.print(")");
  }
}

impl Debug for Call{
  func debug(self, f: Fmt*){
    if(self.scope.is_some()){
      //scope: Option<Box<Expr>>
      let scp: Expr* = self.scope.get();
      if let Expr::Type(t)=scp{
        t.debug(f);
        f.print("::");
      }else{
        scp.debug(f);
        f.print(".");
      }
    }
    f.print(&self.name);
    if(!self.type_args.empty()){
      f.print("<");
      join(f, &self.type_args, ", ");
      f.print(">");
    }
    f.print("(");
    join(f, &self.args, ", ");
    f.print(")");
  }
}

impl Debug for Entry{
  func debug(self, f: Fmt*){
    if(self.isBase){
      f.print(".");
    }else{
    if(self.name.is_some()){
      self.name.get().debug(f);
      f.print(": ");
    }
    }
    self.expr.debug(f);
  }
}
