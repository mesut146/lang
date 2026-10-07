
import std/result
import std/fs

import ast/ast
import ast/parser
import ast/token

static print_cst = false;
//static pretty_print = true;

func format_dir(dir: str, out: str){
    File::create_dir(out)?;
    let files = File::read_dir(dir).unwrap();
    for file in &files{
        let file2 = format("{}/{}", dir, file);
        let outf = format("{}/{}", out, file);
        if(File::is_dir(file2.str())) continue;
        print("file={}\n", file2);
        print("out={}\n", outf);
        let p = Parser::from_path(file2);
        let unit = p.parse_unit();
        let f = Fmt::new();
        debug_unit(&unit, &f, &unit.comments);
        let str = f.buf.clone();
        Drop::drop(f);
        File::write_string(str.str(), outf.str())?;
    }
}

//T: Debug
func join<T>(f: Fmt*, arr: List<T>*, sep: str){
  for(let i = 0;i < arr.len();++i){
    if(i > 0) f.print(sep);
    arr.get(i).debug(f);
  }
}

//Render a node into a standalone string for the "indent every line" trick
//used by body() and debug_impl.
//
//The unit's comment list is threaded through as an explicit side table,
//never stored on Fmt: sub-renders walk the same nodes in the same order,
//so the consume-on-emit marks they leave are exactly what the caller
//would have made. No handle copying, no ownership dance.
func sub_str_stmt(f: Fmt*, comments: List<Comment>*, node: Stmt*): String{
  let sub = Fmt::new();
  debug_stmt(node, &sub, comments);
  let res = sub.buf.clone();
  Drop::drop(sub);
  return res;
}
func sub_str_expr(f: Fmt*, comments: List<Comment>*, node: Expr*): String{
  let sub = Fmt::new();
  debug_expr(node, &sub, comments);
  let res = sub.buf.clone();
  Drop::drop(sub);
  return res;
}
func sub_str_method(f: Fmt*, comments: List<Comment>*, node: Method*): String{
  let sub = Fmt::new();
  debug_method(node, &sub, comments);
  let res = sub.buf.clone();
  Drop::drop(sub);
  return res;
}

//attributes affect semantics (derive/repr/drop): always reprint them
func debug_attrs(list: List<Attribute>*, f: Fmt*){
  for at in list{
    f.print("#");
    f.print(&at.name);
    if(at.is_call){
      f.print("(");
      join(f, &at.args, ", ");
      f.print(")");
    }
    f.print("\n");
  }
}

//Tracks comment/string state across the lines of one sub-render so
//re-indenting never touches lines that already carry their own layout:
//continuations of /* */ comments and of multi-line strings are verbatim
//text, and fmt re-lexes them as such -- indenting them again would push
//them one level deeper on every pass (see emit_lines). Mirrors the
//lexer: comments don't nest, and markers inside strings/chars and after
//a // don't count. All state starts false: a sub-render always begins at
//a node boundary, which is never inside a comment or string.
struct CommentScan{
  in_block: bool;
  in_str: bool;
  in_chr: bool;
}
impl CommentScan{
  func new(): CommentScan{
    return CommentScan{false, false, false};
  }
  //indent for this line ("", i.e. none, when the line starts inside a
  //block comment or string), updating state for the next line.
  func indent_for(self, line: str*, indent: str): str{
    if(self.in_block || self.in_str || self.in_chr){
      self.scan(line);
      return "";
    }
    self.scan(line);
    return indent;
  }
  func scan(self, line: str*){
    let i = 0;
    while(i < line.len()){
      let c = line.get(i) as i8;
      if(self.in_block){
        if(c == '*' && i + 1 < line.len() && line.get(i + 1) as i8 == '/'){
          self.in_block = false;
          i += 2;
          continue;
        }
        i += 1;
        continue;
      }
      if(self.in_str){
        if(c == '\\'){
          i += 2;
          continue;
        }
        if(c == '"'){
          self.in_str = false;
        }
        i += 1;
        continue;
      }
      if(self.in_chr){
        if(c == '\\'){
          i += 2;
          continue;
        }
        if(c == '\''){
          self.in_chr = false;
        }
        i += 1;
        continue;
      }
      if(c == '"'){
        self.in_str = true;
        i += 1;
        continue;
      }
      if(c == '\''){
        self.in_chr = true;
        i += 1;
        continue;
      }
      if(c == '/' && i + 1 < line.len() && line.get(i + 1) as i8 == '/'){
        break;
      }
      if(c == '/' && i + 1 < line.len() && line.get(i + 1) as i8 == '*'){
        self.in_block = true;
        i += 2;
        continue;
      }
      i += 1;
    }
  }
}

func body(node: Stmt*, f: Fmt*, comments: List<Comment>*){
    body(node, f, comments, false);
}

func body(node: Stmt*, f: Fmt*, comments: List<Comment>*, skip_first: bool){
  let str = sub_str_stmt(f, comments, node);
  let lines: List<str> = str.split("\n");
  let scan = CommentScan::new();
  for(let j = 0;j < lines.len();++j){
    //comment/string continuations keep their own layout (see CommentScan)
    let ind = scan.indent_for(lines.get(j), "    ");
    if(j > 0){
        f.print("\n");
    }
    if(j > 0 || !skip_first){
      f.print(ind);
    }
    f.print(lines.get(j));
  }
}

func body(node: Expr*, f: Fmt*, comments: List<Comment>*){
    body(node, f, comments, false);
}

func body(node: Expr*, f: Fmt*, comments: List<Comment>*, skip_first: bool){
  let str = sub_str_expr(f, comments, node);
  let lines: List<str> = str.split("\n");
  let scan = CommentScan::new();
  for(let j = 0;j < lines.len();++j){
    let ind = scan.indent_for(lines.get(j), "    ");
    if(j > 0 || !skip_first){
      f.print(ind);
    }
    f.print(lines.get(j));
    if(j < lines.len() - 1){
        f.print("\n");
    }
  }
}
func body(str: String, f: Fmt*){
    for(let i=0;i<str.len();++i){
        let ch = str.get(i);
        if(ch=='\n'){
        }
        //f.print(ch);
    }
}

impl Debug for QPath{
  func debug(self, f: Fmt*){
    join(f, &self.list, "::");
  }
}

//comment trivia: leading = lines (prev, line), trailing = == line.
//The list is threaded through as a side table (List<Comment>*), never
//stored: Fmt stays a generic buffer and Comment stays an ast type that
//std never names. Emitted entries are consumed (line set to 0) so nested
//containers never re-emit them; ranges overlap by design (a block's range
//sits inside its item's range). Lines are 1-based, so 0 never matches.
func emit_one(f: Fmt*, comments: List<Comment>*, idx: i32, indent: str){
    let c = comments.get(idx);
    f.print(indent);
    f.print(&c.text);
    f.print("\n");
    c.line = 0;
}
func emit_leading(f: Fmt*, comments: List<Comment>*, prev: i32, line: i32, indent: str): i32{
    for(let i = 0;i < comments.len();++i){
        let c = comments.get(i);
        if(c.line > prev && c.line < line){
            emit_one(f, comments, i, indent);
        }
    }
    if(line > prev){
        return line;
    }
    return prev;
}
func emit_trailing(f: Fmt*, comments: List<Comment>*, line: i32){
    if(line <= 0){
        return;
    }
    for(let i = 0;i < comments.len();++i){
        let c = comments.get(i);
        if(c.line == line){
            f.print(" ");
            f.print(&c.text);
            c.line = 0;
        }
    }
}
//limit caps the lines this container may claim, so a comment sitting
//after the container's last token flows outward instead of being
//stolen by the innermost block (e.g. a file trailer after a function's
//closing brace belongs to the file, not to the body).
//limit <= 0 means uncapped (same 0-means-unknown convention as lines).
//The first emitted line gets a leading newline: every container prints
//its last element without a trailing newline, so without it the drain
//would glue the comment onto the closing brace.
func emit_rest(f: Fmt*, comments: List<Comment>*, prev: i32, indent: str, limit: i32): bool{
    let started = false;
    for(let i = 0;i < comments.len();++i){
        let c = comments.get(i);
        if(c.line > prev && (limit <= 0 || c.line <= limit)){
            if(!started){
                f.print("\n");
                started = true;
            }
            emit_one(f, comments, i, indent);
        }
    }
    return started;
}

//start line of a statement's expression.
//
//NB: for block-like expressions this must NOT use Expr's own Node line.
//The parser creates that node after the whole primary expression is
//parsed (see Parser::as_is), so it points *past* the body. Using it
//would make a parent block claim the comments living inside the if /
//match / block body and hoist them above the statement. These variants
//keep their own accurate line, same trick as get_end_line() in utils.x.
func stmt_start_line(e: Expr*): i32{
    match e{
        Expr::If(is) => {
            return is.get().cond.line;
        },
        Expr::IfLet(il) => {
            return il.get().rhs.line;
        },
        Expr::Match(ms) => {
            return ms.get().expr.line;
        },
        Expr::Block(b) => {
            return b.get().line;
        },
        _ => return e.line,
    }
}

//NB: item start lines live in one place only: Item::line() in ast/ast.x.
//Do not add a second dispatch here; the two will drift (they did).
func stmt_line(st: Stmt*): i32{
    match st{
        Stmt::Var(ve) => {
            if(ve.list.empty()){
                return 0;
            }
            //look through to the initializer: parse_frag stamps the
            //fragment's own node AFTER the rhs, so for a multi-line rhs
            //(a lambda body, a match, ...) the fragment line points past
            //its own body and the enclosing block would swallow the body's
            //comments as leading trivia. stmt_start_line() recovers the
            //rhs's true start for exactly the block-like cases that own
            //inner comments; anything else keeps today's behavior.
            let fr = ve.list.get(0);
            return stmt_start_line(&fr.rhs);
        },
        Stmt::Expr(e) => {
            return stmt_start_line(e);
        },
        Stmt::Ret(e) => {
            if(e.is_some()){
                return e.get().line;
            }
            return 0;
        },
        Stmt::While(cond, then) => {
            return cond.line;
        },
        Stmt::For(e) => {
            return 0;
        },
        Stmt::ForEach(fe) => {
            return fe.rhs.line;
        },
        Stmt::Continue => {
            return 0;
        },
        Stmt::Break => {
            return 0;
        }
    }
}

impl Debug for Unit{
  func debug(self, f: Fmt*){
    //single-node diagnostics render comment-free; the file formatter
    //threads the unit's list explicitly through debug_unit()
    let empty = List<Comment>::new();
    debug_unit(self, f, &empty);
  }
}
func debug_unit(self: Unit*, f: Fmt*, comments: List<Comment>*){
    let prev = 0;
    for(let i = 0;i < self.imports.len();++i){
        let im = self.imports.get(i);
        if(i > 0){
            f.print("\n");
        }
        //separator first: leading comments belong to the item that
        //follows them, so they must land after the blank line, not
        //glued to the previous item's last line.
        prev = emit_leading(f, comments, prev, im.line, "");
        im.debug(f);
        emit_trailing(f, comments, im.line);
    }
    if(!self.imports.empty()){
        f.print("\n\n");
    }
    for(let i = 0;i < self.items.len();++i){
        let it = self.items.get(i);
        let ln = it.line();
        if(i > 0){
            f.print("\n\n");
        }
        prev = emit_leading(f, comments, prev, ln, "");
        debug_item(it, f, comments);
        emit_trailing(f, comments, ln);
    }
    //no limit: the file claims every remaining comment.
    emit_rest(f, comments, prev, "", 0);
}


impl Debug for ImportStmt{
  func debug(self, f: Fmt*){
    f.print("import ");
    join(f, &self.list, "/");
  }
}

impl Debug for ExternItem {
  func debug(self, f: Fmt*){
    match self{
      ExternItem::Method(m) => m.debug(f),
      ExternItem::Global(gl) => gl.debug(f),
    }
  }
}

impl Debug for Item{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_item(self, f, &empty);
  }
}
func debug_item(self: Item*, f: Fmt*, comments: List<Comment>*){
    match self{
      Item::Decl(decl) => {
        if(print_cst) f.print("Item::Decl{\n");
        debug_decl(decl, f, comments);
        if(print_cst) f.print("}");
      },
      Item::Method(m) => {
        debug_method(m, f, comments);
      },
      Item::Impl(i) => {
        debug_impl(i, f, comments);
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
        f.print("{\n");
        //same reasoning as enum: keep comments between the trait's
        //methods inside the trait body instead of letting the next
        //file-level item claim them.
        let prev = 0;
        for(let i = 0;i < tr.methods.len();++i){
          let m = tr.methods.get(i);
          if(i > 0){
            f.print("\n");
          }
          prev = emit_leading(f, comments, prev, m.line, "");
          debug_method(m, f, comments);
          emit_trailing(f, comments, m.line);
        }
        //no trailing drain: like Decl, Trait carries no end line, and an
        //uncapped drain here would swallow every later comment in the
        //file (including ones inside the next item's body).
        f.print("\n}");
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
        f.print(";");
      },
      Item::Glob(gl) => {
        gl.debug(f);
      },
      Item::Module(md) => {
        debug_module(md, f, comments);
      },
      Item::Use(uit) => {
        Debug::debug(uit, f);
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
    }
    //single form (use M::A) carries the item as the last path segment
    //and scope form (use M) as the whole path; neither has a list.
    f.print(";");
  }
}

impl Debug for Module{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_module(self, f, &empty);
  }
}
func debug_module(self: Module*, f: Fmt*, comments: List<Comment>*){
    f.print("mod ");
    Debug::debug(&self.name, f);
    f.print("{\n");
    //start from the `mod` keyword so comments between it and the first
    //item stay inside this module.
    let prev = self.start_line;
    for(let i = 0;i < self.items.len();++i){
        let it = self.items.get(i);
        let ln = it.line();
        if(i > 0){
            f.print("    \n");
        }
        prev = emit_leading(f, comments, prev, ln, "");
        debug_item(it, f, comments);
        emit_trailing(f, comments, ln);
    }
    //capped at the module's own closing brace: a comment below it
    //belongs to the enclosing file, not to this module body.
    //the drain already ended the line, so only add the newline that
    //separates the body from `}` when it emitted nothing.
    if(!emit_rest(f, comments, prev, "", self.end_line)){
        f.print("\n");
    }
    f.print("}");
}

impl Debug for Global{
  func debug(self, f: Fmt*){
    f.print("static ");
    f.print(self.name.str());
    if(self.type.is_some()){
      f.print(": ");
      self.type.get().debug(f);
    }
    //expr is Option (uninitialized statics parse but fail resolve);
    //only initialized ones round-trip through here in practice
    if(self.expr.is_some()){
      f.print(" = ");
      self.expr.get().debug(f);
    }
    f.print(";");
  }
}

impl Debug for Impl{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_impl(self, f, &empty);
  }
}
func debug_impl(self: Impl*, f: Fmt*, comments: List<Comment>*){
    self.info.debug(f);
    f.print("{\n");
    for(let i=0;i<self.methods.len();++i){
        if(i>0){
            f.print("\n");
        }
      let ms = sub_str_method(f, comments, self.methods.get(i));
      let lines = ms.str().split("\n");
      let scan = CommentScan::new();
      for(let j = 0;j < lines.len();++j){
        f.print(scan.indent_for(lines.get(j), "    "));
        f.print(lines.get(j));
        f.print("\n");
      }
    }
    f.print("\n}");
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
      //see Unit: diagnostics render comment-free
      let empty = List<Comment>::new();
      debug_decl(self, f, &empty);
    }
}
func debug_decl(self: Decl*, f: Fmt*, comments: List<Comment>*){
      match self{
        Decl::Struct(fields) => {
            debug_struct(self, fields, f, comments);
        },
        Decl::Enum(variants) => {
            debug_enum(self, variants, f, comments);
        },
        Decl::TupleStruct(fields) => {
          debug_struct_tuple(self, fields, f);
        }
      }
    }
    func debug_struct(decl: Decl*, fields: List<FieldDecl>*, f: Fmt*, comments: List<Comment>*){
        debug_attrs(&decl.attr.list, f);
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
      debug_attrs(&decl.attr.list, f);
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


  func debug_enum(decl: Decl*, variants: List<Variant>*, f: Fmt*, comments: List<Comment>*){
      debug_attrs(&decl.attr.list, f);
      f.print("enum ");
      decl.type.debug(f);
      if(decl.base.is_some()){
        f.print(": ");
        decl.base.get().debug(f);
      }
      f.print("{\n");
      //drain inside the enum body so comments between variants are not
      //claimed by whatever item follows the enum at file level.
      let prev = decl.line;
      for(let i = 0;i < variants.len();++i){
        let ev = variants.get(i);
        prev = emit_leading(f, comments, prev, ev.line, "    ");
        f.print("    ");
        f.print(&ev.name);
        if(ev.disc.is_some()){
          f.print(" = ");
          ev.disc.get().debug(f);
        }
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
        //after the comma: `A, // note` is the source form, and printing
        //the comment first would yield the unparseable `A // note,`.
        emit_trailing(f, comments, ev.line);
        f.print("\n");
      }
      //no trailing drain here: Decl carries no end line, so a comment
      //after the last variant cannot be told apart from one sitting
      //below the enum's closing brace. Letting the next file-level item
      //claim it only costs indentation; draining here could swallow a
      //file comment into the enum body.
      f.print("}");
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
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_method(self, f, &empty);
  }
}
func debug_method(self: Method*, f: Fmt*, comments: List<Comment>*){
    debug_attrs(&self.attr.list, f);
    f.print("func ");
    f.print(&self.name);
    if(!self.type_params.empty()){
      f.print("<");
      join(f, &self.type_params, ", ");
      f.print(">");
    }
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
      debug_block(self.body.get(), f, comments);
    }else{
      f.print(";");
    }
}

impl Debug for Param{
  func debug(self, f: Fmt*){
    //self params print bare under their declared name (self, *self, x1):
    //an explicit `: Type` would re-parse as a regular parameter and
    //break method resolution.
    if(self.is_self){
      if(self.is_deref){
        f.print("*");
      }
      f.print(&self.name);
      return;
    }
    if(self.is_deref){
      f.print("*");
    }
    f.print(&self.name);
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

impl Debug for LambdaParam{
  func debug(self, f: Fmt*){
    f.print(&self.name);
    if(self.type.is_some()){
      f.print(": ");
      self.type.get().debug(f);
    }
  }
}
impl Debug for LambdaType{  func debug(self, f: Fmt*){
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
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_stmt(self, f, &empty);
  }
}
func debug_stmt(self: Stmt*, f: Fmt*, comments: List<Comment>*){
    match self{
      Stmt::Var(ve)=>{
        f.print("let ");
        debug_varexpr(ve, f, comments);
        f.print(";");
      },
      Stmt::Expr(e) => {
        if(print_cst) f.print("Stmt::Expr{\n");
        debug_expr(e, f, comments);
        if(!e.is_body()){
          f.print(";");
        }
        if(print_cst) f.print("}\n");
      },
      Stmt::Ret(e) =>{
        f.print("return");
        if(e.is_some()){
          f.print(" ");
          debug_expr(e.get(), f, comments);
        }
        f.print(";");
      },
      Stmt::While(e, b)=>{
        f.print("while(");
        debug_expr(e, f, comments);
        f.print(")");
        debug_body(b.get(), f, comments);
      },
      Stmt::For(fs)=>{
        f.print("for(");
        if(fs.var_decl.is_some()){
          f.print("let ");
          debug_varexpr(fs.var_decl.get(), f, comments);
        }
        f.print(";");
        if(fs.cond.is_some()){
          debug_expr(fs.cond.get(), f, comments);
        }
        f.print(";");
        for(let i = 0;i < fs.updaters.len();++i){
          if(i > 0) f.print(", ");
          debug_expr(fs.updaters.get(i), f, comments);
        }
        f.print(")");
        debug_body(fs.body.get(), f, comments);
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
        debug_expr(&fe.rhs, f, comments);
        debug_block(&fe.body, f, comments);
      }
    }
}

impl Debug for Body{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_body(self, f, &empty);
  }
}
func debug_body(self: Body*, f: Fmt*, comments: List<Comment>*){
    match self{
      Body::Block(b)=>{
        if(print_cst) f.print("Body::Block{\n");
        debug_block(b, f, comments);
        if(print_cst) f.print("}\n");
      },
      Body::Stmt(b)=>{
        if(print_cst) f.print("Body::Stmt{\n");
        debug_stmt(b, f, comments);
        if(print_cst) f.print("}\n");
      },
      Body::If(b)=>{
        if(print_cst) f.print("Body::If{\n");
        debug_ifstmt(b, f, comments);
        if(print_cst) f.print("}\n");
      },
      Body::IfLet(b)=>{
        if(print_cst) f.print("Body::IfLet{\n");
        debug_iflet(b, f, comments);
        if(print_cst) f.print("}\n");
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
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_block(self, f, &empty);
  }
}
func debug_block(self: Block*, f: Fmt*, comments: List<Comment>*){
    f.print("{\n");
    let prev = 0;
    for(let i = 0;i < self.list.len();++i){
        let ln = stmt_line(self.list.get(i));
        if(i>0) f.print("\n");
        prev = emit_leading(f, comments, prev, ln, "    ");
        body(self.list.get(i), f, comments);
        emit_trailing(f, comments, ln);
    }
    if(self.return_expr.is_some()){
        if(!self.list.empty()){
            f.print("\n");
        }
      if(print_cst) f.print("Block::return_expr{\n");
      //NB: the tail expression is rendered BEFORE the drain below. A
      //block whose only content is a block-like expression (a function
      //whose sole statement is an `if`, for example) keeps that
      //expression as its return_expr, and its nested body owns the
      //comments inside it. Draining first would hoist them above the
      //statement they belong to.
      body(self.return_expr.get(), f, comments);
      if(print_cst) f.print("}\n");
    }
    //capped at the body's closing brace so a comment after the function
    //stays a file comment instead of being pulled into the last block.
    //runs last so whatever the tail expression did not claim is still
    //placed inside this body.
    //a drain ends its own last line, so `}` needs no leading newline;
    //every other path leaves the stream mid-line and needs one.
    if(emit_rest(f, comments, prev, "    ", self.end_line)){
        f.print("}");
    }else{
        f.print("\n}");
    }
}

impl Debug for VarExpr{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_varexpr(self, f, &empty);
  }
}
func debug_varexpr(self: VarExpr*, f: Fmt*, comments: List<Comment>*){
    //multi-declarator fragments (let i = 0, j = 1) need separators
    for(let i = 0;i < self.list.len();++i){
      if(i > 0) f.print(", ");
      debug_fragment(self.list.get(i), f, comments);
    }
}

impl Debug for Fragment{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_fragment(self, f, &empty);
  }
}
func debug_fragment(self: Fragment*, f: Fmt*, comments: List<Comment>*){
    f.print(&self.name);
    if(self.type.is_some()){
      f.print(": ");
      self.type.get().debug(f);
    }
    f.print(" = ");
    debug_expr(&self.rhs, f, comments);
}

impl Debug for Literal{
  func debug(self, f: Fmt*){
    //escape backslash first (others introduce backslashes themselves),
    //then the rest; the lexer decodes them back via checkEscape.
    //chained (no temporaries to reassign).
    let replaced = self.val.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t").replace("\"", "\\\"").replace("'", "\\'");
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
  }
}

//expr---------------------------------
impl Debug for Expr{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_expr(self, f, &empty);
  }
}
func debug_expr(self: Expr*, f: Fmt*, comments: List<Comment>*){
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
        debug_call(call, f, comments);
      },
      Expr::Par(e) => {
        if(print_cst) f.print("Expr::Par{");
        f.print("(");
        debug_expr(e.get(), f, comments);
        f.print(")");
      },
      Expr::Tuple(elems) => {
        if(print_cst) f.print("Expr::Tuple{");
        f.print("(");
        for(let i = 0;i < elems.len();++i){
          if(i > 0) f.print(",");
          debug_expr(elems.get(i), f, comments);
        }
        //single-element tuples need the comma or they re-parse as parens
        if(elems.len() == 1){
          f.print(",");
        }
        f.print(")");
      },
      Expr::Type(t) => {
        if(print_cst) f.print("Expr::Type{");
        t.debug(f);
      },
      Expr::Unary(op, e) => {
        if(print_cst) f.print("Expr::Unary{");
        f.print(op);
        debug_expr(e.get(), f, comments);
      },
      Expr::Infix(op, l, r) => {
        if(print_cst) f.print("Expr::Infix{");
        debug_expr(l.get(), f, comments);
        f.print(" ");
        f.print(op);
        f.print(" ");
        debug_expr(r.get(), f, comments);
      },
      Expr::Access(scp, nm) => {
        if(print_cst) f.print("Expr::Access{");
        debug_expr(scp.get(), f, comments);
        f.print(".");
        f.print(nm);
      },
      Expr::Obj(ty, args) => {
        if(print_cst) f.print("Expr::Obj{");
        ty.debug(f);
        f.print("{");
        for(let i = 0;i < args.len();++i){
          if(i > 0) f.print(", ");
          debug_entry(args.get(i), f, comments);
        }
        f.print("}");
      },
      Expr::As(e, type) => {
        if(print_cst) f.print("Expr::As{");
        debug_expr(e.get(), f, comments);
        f.print(" as ");
        type.debug(f);
      },
      Expr::Is(e, rhs) => {
        if(print_cst) f.print("Expr::Is{");
        debug_expr(e.get(), f, comments);
        f.print(" is ");
        debug_expr(rhs.get(), f, comments);
      },
      Expr::Array(arr, sz) => {
        if(print_cst) f.print("Expr::Array{");
        f.print("[");
        for(let i = 0;i < arr.len();++i){
          if(i > 0) f.print(", ");
          debug_expr(arr.get(i), f, comments);
        }
        if(sz.is_some()){
          f.print("; ");
          sz.get().debug(f);
        }
        f.print("]");
      },
      Expr::ArrAccess(aa) => {
        if(print_cst) f.print("Expr::ArrAccess{");
        debug_expr(aa.arr.get(), f, comments);
        f.print("[");
        debug_expr(aa.idx.get(), f, comments);
        if(aa.idx2.is_some()){
          f.print("..");
          debug_expr(aa.idx2.get(), f, comments);
        }
        f.print("]");
      },
      Expr::Block(b) => {
        if(print_cst) f.print("Expr::Block{");
        debug_block(b.get(), f, comments);
      },
      Expr::If(ife) => {
        if(print_cst) f.print("Expr::If{");
        debug_ifstmt(ife.get(), f, comments);
      },
      Expr::IfLet(il) => {
        if(print_cst) f.print("Expr::IfLet{");
        debug_iflet(il.get(), f, comments);
      },
      Expr::Match(me) => {
        if(print_cst) f.print("Expr::Match{");
        debug_match(me.get(), f, comments);
      },
      Expr::MacroCall(mc) => {
        debug_macrocall(mc, f, comments);
      },
      Expr::Lambda(lc) => {
          f.print("|");
          join(f, &lc.params, ", ");
          f.print("|");
          if(lc.return_type.is_some()){
              f.print(": ");
              f.print(lc.return_type.get());
          }
          match (lc.body.get()){
              LambdaBody::Expr(e)=>{
                  body(e, f, comments, true);
              },
              LambdaBody::Stmt(s)=>{
                  body(s, f, comments, true);
              }
          }
      },
      Expr::Ques(bx) => {
        if(print_cst) f.print("Expr::Ques{");
        debug_expr(bx.get(), f, comments);
        f.print("?");
      }
    }
    if(print_cst) f.print("}");
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
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_match(self, f, &empty);
  }
}
func debug_match(self: Match*, f: Fmt*, comments: List<Comment>*){
    f.print("match ");
    debug_expr(&self.expr, f, comments);
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
          body(expr, f, comments, true);
        },
        MatchRhs::STMT(stmt)=>{
          body(stmt, f, comments, true);
        }
      }
      if(i < self.cases.len() - 1){
          f.print(",\n");
      }
    }
    f.print("\n}\n");
}

impl Debug for IfStmt{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_ifstmt(self, f, &empty);
  }
}
func debug_ifstmt(self: IfStmt*, f: Fmt*, comments: List<Comment>*){
    f.print("if(");
    debug_expr(&self.cond, f, comments);
    f.print(")");
    if(!(self.then.get() is Body::Block)){
      f.print(" ");
    }
    debug_body(self.then.get(), f, comments);
    if(self.else_stmt.is_some()){
      f.print("\nelse ");
      let els = self.else_stmt.get();
      debug_body(els, f, comments);
    }
}

impl Debug for IfLet{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_iflet(self, f, &empty);
  }
}
func debug_iflet(self: IfLet*, f: Fmt*, comments: List<Comment>*){
    f.print("if let ");
    self.type.debug(f);
    //empty parens do not re-parse: only fieldless variants omit them
    if(!self.args.empty()){
      f.print("(");
      join(f, &self.args, ", ");
      f.print(")");
    }
    f.print(" = ");
    debug_expr(&self.rhs, f, comments);
    debug_body(self.then.get(), f, comments);
    if(self.else_stmt.is_some()){
      f.print("else ");
      debug_body(self.else_stmt.get(), f, comments);
    }
}

impl Debug for MacroCall{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_macrocall(self, f, &empty);
  }
}
func debug_macrocall(self: MacroCall*, f: Fmt*, comments: List<Comment>*){
    if(self.scope.is_some()){
      Debug::debug(self.scope.get(), f);
      f.print("::");
    }
    f.print(&self.name);
    f.print("!(");
    for(let i = 0;i < self.args.len();++i){
      if(i > 0) f.print(", ");
      debug_expr(self.args.get(i), f, comments);
    }
    f.print(")");
}

impl Debug for Call{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_call(self, f, &empty);
  }
}
func debug_call(self: Call*, f: Fmt*, comments: List<Comment>*){
    if(self.scope.is_some()){
      //scope: Option<Box<Expr>>
      let scp: Expr* = self.scope.get();
      if let Expr::Type(t)=scp{
        t.debug(f);
        f.print("::");
      }else{
        debug_expr(scp, f, comments);
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
    for(let i = 0;i < self.args.len();++i){
      if(i > 0) f.print(", ");
      debug_expr(self.args.get(i), f, comments);
    }
    f.print(")");
}

impl Debug for Entry{
  func debug(self, f: Fmt*){
    //see Unit: diagnostics render comment-free
    let empty = List<Comment>::new();
    debug_entry(self, f, &empty);
  }
}
func debug_entry(self: Entry*, f: Fmt*, comments: List<Comment>*){
    if(self.isBase){
      f.print(".");
    }else{
    if(self.name.is_some()){
      self.name.get().debug(f);
      f.print(": ");
    }
    }
    debug_expr(&self.expr, f, comments);
}
