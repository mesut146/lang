import parser/lexer
import parser/token
import parser/ast
import parser/printer
import std/map
import std/libc

//#derive(Drop)
class Parser{
  lexer: Lexer;
  tokens: List<Token>;
  pos: i32;
  is_marked: bool;
  mark: i32;
  unit: Option<Unit*>;
}

impl Drop for Parser{
  func drop(self){
    self.lexer.drop();
    self.tokens.drop();
  }
}

impl Parser{
  
  func new(path: String): Parser{
    let lexer = Lexer::new(path);
    let res = Parser{lexer, List<Token>::new(), 0, false, 0, Option<Unit*>::new()};
    res.fill();
    return res;
  }
  
  func fill(self) {
    while (true) {
        let t = self.lexer.next();
        if (t.is(TokenType::EOF_))
            break;
        if (t.is(TokenType::COMMENT))
            continue;
        self.tokens.add(t);
      }
      //print("tokens %d %s\n", self.tokens.len(), self.lexer.path.cstr());
    }
    
    func has(self): bool{
      return self.pos < self.tokens.len();
    }
    
    func is(self, tt: TokenType): bool{
      return self.has() && self.peek().type is tt;
    }
    
    func is(self, tt1: TokenType, tt2: TokenType): bool{
      return self.has() && self.peek().type is tt1 && self.peek(1).type is tt2;
    }
    
    func peek(self): Token*{
      return self.get(self.pos);
    }
    
    func peek(self, la: i32): Token*{
      return self.get(self.pos + la);
    }
    
    func get(self, pos: i32): Token*{
      if(pos >= self.tokens.len()) panic("eof");
      return self.tokens.get_ptr(pos);
    }
    
    func pop(self): Token*{
      let t = self.peek();
      ++self.pos;
      return t;
    }
    
    func popv(self): String{
    	return self.pop().value.clone();
    }
    
    func consume(self, tt: TokenType): Token*{
      let t = self.pop();
      if(t.type is tt) return t;
      print("%s:%d\n", self.lexer.path.cstr(), t.line);
      panic("unexpected token %s was expecting %s", t.print().cstr(), Fmt::str(&tt).cstr());
    }
    
    func parse_unit(self): Unit{
      let unit = Unit::new(self.lexer.path.str());
      self.unit = Option::new(&unit);
      while(self.has() && self.is(TokenType::IMPORT)){
        unit.imports.add(self.parse_import());
      }
      while(self.has()){
        let derives = List<Type>::new();
        let attr = List<String>::new();
        if(self.is(TokenType::HASH)){
          self.pop();
          let name = self.consume(TokenType::IDENT);
          if(name.value.eq("derive")){
            self.consume(TokenType::LPAREN);
            derives.add(self.parse_type());
            while(self.is(TokenType::COMMA)){
              self.pop();
              derives.add(self.parse_type());
            }
            self.consume(TokenType::RPAREN);
          }else if(name.value.eq("drop")){
            attr.add(name.value.clone());
          }else{
            panic("invalid attr %s", name.value.cstr());
          }
        }
        if(self.is(TokenType::CLASS) || self.is(TokenType::STRUCT)){
          unit.items.add(Item::Decl{self.parse_struct(derives, attr)});
        }else if(self.is(TokenType::ENUM)){
          unit.items.add(Item::Decl{self.parse_enum(derives, attr)});
        }else if(self.is(TokenType::IMPL)){
          unit.items.add(Item::Impl{self.parse_impl()});
        }else if(self.is(TokenType::TRAIT)){
          unit.items.add(Item::Trait{self.parse_trait()});
        }else if(self.is(TokenType::FUNC)){
          unit.items.add(Item::Method{self.parse_method(Option<Type>::None, Parent::None)});
        }else if(self.is(TokenType::TYPE)){
          self.pop();
          let name = self.name();
          self.consume(TokenType::EQ);
          let rhs = self.parse_type();
          self.consume(TokenType::SEMI);
          unit.items.add(Item::Type{name: name, rhs: rhs});
        }else if(self.is(TokenType::EXTERN)){
          self.pop();
          let list = self.parse_methods(Option<Type>::None, Parent::Extern);
          unit.items.add(Item::Extern{methods: list});
        }else if(self.is(TokenType::STATIC)){
        	self.pop();
            let name = self.name();
            let type = Option<Type>::None;
            if(self.is(TokenType::COLON)){
              self.pop();
              type = Option::new(self.parse_type());
            }
            self.consume(TokenType::EQ);
            let rhs = self.parse_expr();
            self.consume(TokenType::SEMI);
            unit.globals.add(Global{name, type, rhs});
        }else{
          panic("invalid top level decl: %s", self.peek().print().cstr());
        }
      }
      return unit;
    }

    func parse_trait(self): Trait{
      self.consume(TokenType::TRAIT);
      let type = self.parse_type();
      let res = Trait{type, List<Method>::new()};
      self.consume(TokenType::LBRACE);
      while (!self.is(TokenType::RBRACE)) {
          let parent = Parent::Trait{type: type.clone()};
          res.methods.add(self.parse_method(Option::new(type), parent));
      }
      self.consume(TokenType::RBRACE);
      return res;
    }
    
    func parse_import(self): ImportStmt{
      self.consume(TokenType::IMPORT);
      let res = ImportStmt{list: List<String>::new()};
      res.list.add(self.popv());
      while(self.is(TokenType::DIV)){
        self.pop();
        res.list.add(self.popv());
      }
      return res;
    }
    
    func parse_impl(self): Impl{
        self.consume(TokenType::IMPL);
        let type_params = List<Type>::new();
        if (self.is(TokenType::LT)) {
          type_params = self.type_params();
        }
        let t1 = self.parse_type();
        if(self.is(TokenType::FOR)){
            self.pop();
            let target = self.parse_type();
            let op = Option::new(target.clone());
            let info = ImplInfo{type_params, Option::new(t1), target};
            let parent = Parent::Impl{info};
            return Impl{info, self.parse_methods(op, parent)};
        }else{
          let op = Option::new(t1.clone());
          let info = ImplInfo{type_params, Option<Type>::None, t1};
          let parent = Parent::Impl{info};
          return Impl{info, self.parse_methods(op, parent)};
        }
        panic("parse_impl");
    }
    
    func parse_methods(self, imp: Option<Type>, parent: Parent): List<Method>{
        let arr = List<Method>::new();
        self.consume(TokenType::LBRACE);
        while(!self.is(TokenType::RBRACE)){
            arr.add(self.parse_method(imp, parent));
        }
        self.consume(TokenType::RBRACE);
        return arr;
    }
    
    func parse_method(self, imp: Option<Type>, parent: Parent): Method{
      if(self.is(TokenType::VIRTUAL)){
        self.pop();
      }
      self.consume(TokenType::FUNC);
      let line = self.node();
      let name = self.popv();
      let type_args = List<Type>::new();
      let is_generic = false;
      if(self.is(TokenType::LT)){
        type_args = self.type_params();
        is_generic = true;
      }
      if let Parent::Impl(info*)=(parent){
        if(!info.type_params.empty()){
          is_generic = true;
        }
      }
      self.consume(TokenType::LPAREN);
      let params = List<Param>::new();
      let selfp = Option<Param>::None;
      if(!self.is(TokenType::RPAREN)){
        if(Parser::isName(self.peek()) && self.peek(1).is(TokenType::COLON)){
          params.add(self.parse_param());
        }else{
          let id = self.node();
          let self_name = self.name();
          let self_ty = imp.get().toPtr();
          selfp = Option::new(Param{.id, self_name, self_ty, true});
        }
        while (self.is(TokenType::COMMA)) {
            self.consume(TokenType::COMMA);
            params.add(self.parse_param());
        }
      }
      self.consume(TokenType::RPAREN);
      let type = Option<Type>::None;
      if(self.is(TokenType::COLON)){
        self.pop();
        type = Option::new(self.parse_type());
      }else{
        type = Option::new(Type::new("void".str()));
      }
      let body = Option<Block>::None;
      if(self.is(TokenType::SEMI)){
        self.pop();
      }else{
        let bl = self.parse_block();
        body = Option::new(bl);
      }
      let res = Method{.line, type_args, name, selfp, params, type.unwrap(), body, is_generic, parent, self.lexer.path.clone()};
      return res;
    }
    
    func parse_param(self): Param{
      let id = self.node();
      let name = self.pop();
      self.consume(TokenType::COLON);
      let type = self.parse_type();
      return Param{.id, name.value, type, false};
    }
    
    func parse_struct(self, derives: List<Type>, attr: List<String>): Decl{
      let line = self.peek().line;
      if(self.is(TokenType::CLASS)){
        self.consume(TokenType::CLASS);
      }else{
        self.consume(TokenType::STRUCT);
      }
      let type = self.parse_type();
      let is_generic = type.is_generic();
      //isgen
      let base = Option<Type>::None;
      if(self.is(TokenType::COLON)){
        self.pop();
        base = Option<Type>::Some{self.parse_type()};
      }
      let fields = List<FieldDecl>::new();
      if(self.is(TokenType::SEMI)){
        self.pop();
      }else{
        self.consume(TokenType::LBRACE);
        while(!self.is(TokenType::RBRACE)){
          fields.add(self.parse_field(true));
        }
        self.consume(TokenType::RBRACE);
      }
      let path = self.lexer.path.clone();
      return Decl::Struct{.BaseDecl{line, path, type, false, is_generic, base, derives, attr}, fields: fields};
    }
    
    func parse_field(self, semi: bool): FieldDecl{
      let line=self.peek().line;
      let name = self.popv();
      self.consume(TokenType::COLON);
      let type=self.parse_type();
      if(semi){
        self.consume(TokenType::SEMI);
      }
      return FieldDecl{name, type};
    }
    
    func parse_enum(self, derives: List<Type>, attr: List<String>): Decl{
      let line = self.peek().line;
      self.consume(TokenType::ENUM);
      let type = self.parse_type();
      let is_generic = type.is_generic();
      //isgen
      let base = Option<Type>::None;
      if(self.is(TokenType::COLON)){
        self.pop();
        base = Option<Type>::Some{self.parse_type()};
      }
      self.consume(TokenType::LBRACE);
      let variants = List<Variant>::new();
      variants.add(self.parse_variant());
      while(self.is(TokenType::COMMA)){
        self.pop();
        variants.add(self.parse_variant());
      }
      self.consume(TokenType::RBRACE);
      let path = self.lexer.path.clone();
      return Decl::Enum{.BaseDecl{line, path, type, false, is_generic, base, derives, attr}, variants: variants};
    }
    
    func parse_variant(self): Variant{
      let name = self.name();
      let fields = List<FieldDecl>::new();
      if(self.is(TokenType::LPAREN)){
        self.pop();
        fields.add(self.parse_field(false));
        while(self.is(TokenType::COMMA)){
          self.pop();
          fields.add(self.parse_field(false));
        }
        self.consume(TokenType::RPAREN);
      }
      return Variant{name, fields};
    }
    
    func parse_type(self): Type{
      let res = Type::new("");
      if(self.is(TokenType::LBRACKET)){
        self.pop();
        let type = self.parse_type();
        if(self.is(TokenType::SEMI)){
          self.pop();
          let size = self.consume(TokenType::INTEGER_LIT);
          self.consume(TokenType::RBRACKET);
          let bx: Box<Type> = Box::new(type);
          //res.drop();
          res = Type::Array{bx,  i32::parse(size.value.str())};
        }else{
          self.consume(TokenType::RBRACKET);
          //res.drop();
          res = Type::Slice{Box::new(type)};
        }
      }else{
        //res.drop();
        res = self.gen_part();
        while(self.is(TokenType::COLON2)){
          self.pop();
          let part = self.gen_part();
          if let Type::Simple(smp*) = (part){
            //res.drop();nope
            res = Type::Simple{Simple{Ptr::new(res), smp.name, smp.args}};
          }
        }
      }
      while (self.is(TokenType::STAR)) {
        self.consume(TokenType::STAR);
        res = Type::Pointer{Box::new(res)};
      }
      return res;
    }
    
    func gen_part(self): Type{
      //a<b>::c<d>
      let id = self.popv();
      if(self.is(TokenType::LT)){
        return Simple{Ptr<Type>::new(), id, self.generics()}.into();
      }
      return Simple{Ptr<Type>::new(), id, List<Type>::new()}.into();
    }
    
    func generics(self): List<Type>{
      let res = List<Type>::new();
      self.consume(TokenType::LT);
      res.add(self.parse_type());
      while(self.is(TokenType::COMMA)){
        self.pop();
        res.add(self.parse_type());
      }
      self.consume(TokenType::GT);
      return res;
    }
    
    func type_params(self): List<Type>{
      let res = List<Type>::new();
      self.consume(TokenType::LT);
      res.add(self.parse_tp());
      while(self.is(TokenType::COMMA)){
        self.pop();
        res.add(self.parse_tp());
      }
      self.consume(TokenType::GT);
      return res;
    }
    
    func parse_tp(self): Type{
        let id = self.popv();
        return Type::new(id);
    }
}

//statements
impl Parser{
  func parse_block(self): Block{
      self.consume(TokenType::LBRACE);
      let arr = List<Stmt>::new();
      while(!self.is(TokenType::RBRACE)){
        arr.add(self.parse_stmt());
        //dump(arr.last());
      }
      self.consume(TokenType::RBRACE);
      let res = Block{arr};
      return res;
    }
    
    func var(self): VarExpr{
        self.pop();
        let vd = VarExpr::new();
        vd.list.add(self.parse_frag());
        while(self.is(TokenType::COMMA)){
          self.pop();
          vd.list.add(self.parse_frag());
        }
        return vd;
    }

    func parse_bind(self): ArgBind{
      let name = self.name();
      let id = self.node();
      if(self.is(TokenType::STAR)){
        self.pop();
        return ArgBind{.id, name, true};
      }
      return ArgBind{.id, name, false};
    }
    
    func parse_stmt(self): Stmt{
      if(self.is(TokenType::LBRACE)){
        let res = Stmt::Block{self.parse_block()};
        return res;
      }
      else if(self.is(TokenType::LET)){
        let vd = self.var();
        self.consume(TokenType::SEMI);
        return Stmt::Var{vd};
      }else if(self.is(TokenType::RETURN)){
        self.pop();
        if(self.is(TokenType::SEMI)){
          self.consume(TokenType::SEMI);
          return Stmt::Ret{Option<Expr>::None};
        }else{
          let e = self.parse_expr();
          self.consume(TokenType::SEMI);
          return Stmt::Ret{Option::new(e)};
        }
      }else if(self.is(TokenType::WHILE)){
        self.pop();
        self.consume(TokenType::LPAREN);
        let e = self.parse_expr();
        self.consume(TokenType::RPAREN);
        let b = self.parse_block();
        return Stmt::While{e, b};
      }else if(self.is(TokenType::IF, TokenType::LET)){
        self.pop();
        self.consume(TokenType::LET);
        let ty = self.parse_type();
        let args = List<ArgBind>::new();
        if(self.is(TokenType::LPAREN)){
          self.consume(TokenType::LPAREN);
          args.add(self.parse_bind());
          while(self.is(TokenType::COMMA)){
            self.pop();
            args.add(self.parse_bind());
          }
          self.consume(TokenType::RPAREN);
        }
        self.consume(TokenType::EQ);
        self.consume(TokenType::LPAREN);
        let rhs = self.parse_expr();
        self.consume(TokenType::RPAREN);
        let then = self.parse_stmt();
        let els = Option<Box<Stmt>>::None;
        if(self.is(TokenType::ELSE)){
            self.pop();
            els = Option::new(Box::new(self.parse_stmt()));
        }
        return Stmt::IfLet{IfLet{ty, args, rhs, Box::new(then), els}};
      }else if(self.is(TokenType::IF)){
        self.pop();
        self.consume(TokenType::LPAREN);
        let e = self.parse_expr();
        self.consume(TokenType::RPAREN);
        let b = Box::new(self.parse_stmt());
        if(self.is(TokenType::ELSE)){
          self.pop();
          let els = self.parse_stmt();
          return Stmt::If{IfStmt{e, b, Option::new(Box::new(els))}};
        }
        return Stmt::If{IfStmt{e, b, Option<Box<Stmt>>::None}};
      }else if(self.is(TokenType::FOR)){
        self.pop();
        self.consume(TokenType::LPAREN);
        let v = Option<VarExpr>::None;
        if(!self.is(TokenType::SEMI)){
          v = Option::new(self.var());
        }
        self.consume(TokenType::SEMI);
        let e = Option<Expr>::None;
        if(!self.is(TokenType::SEMI)){
          e = Option::new(self.parse_expr());
        }
        self.consume(TokenType::SEMI);
        let u = self.exprList(TokenType::RPAREN);
        self.consume(TokenType::RPAREN);
        let b = self.parse_stmt();
        return Stmt::For{ForStmt{v, e, u, Box::new(b)}};
      }else if(self.is(TokenType::CONTINUE)){
        self.pop();
        self.consume(TokenType::SEMI);
        return Stmt::Continue;
      }else if(self.is(TokenType::BREAK)){
        self.pop();
        self.consume(TokenType::SEMI);
        return Stmt::Break;
      }else if(self.is(TokenType::ASSERT_KW)){
        self.pop();
        let e = self.parse_expr();
        self.consume(TokenType::SEMI);
        return Stmt::Assert{e};
      }else{
        let e = self.parse_expr();
        self.consume(TokenType::SEMI);
        return Stmt::Expr{e};
      }
      panic("invalid stmt %s", self.peek().print().cstr());
    }
    
    func parse_frag(self): Fragment{
      let nm = self.pop();
      let type = Option<Type>::None;
      if(self.is(TokenType::COLON)){
        self.pop();
        type = Option::new(self.parse_type());
      }
      self.consume(TokenType::EQ);
      let rhs = self.parse_expr();
      let n = self.node();
      return Fragment{.n, nm.value, type, rhs};
    }

    func node(self): Node{
      return Node::new(++self.unit.unwrap().last_id, self.peek().line);
    }
}


//expr
impl Parser{
  func isName(tok: Token*): bool{
    let t = tok.type;
    return t is TokenType::IDENT || t is TokenType::IS || t is TokenType::AS || t is TokenType::TYPE || t is TokenType::TRAIT || t is TokenType::NEW;
  }
  
  func isTypeArg(self, pos: i32): i32{
    if (!self.get(pos).is(TokenType::LT)) {
        return -1;
    }
    pos+=1;
    let open = 1;
    while (pos < self.tokens.len()) {
      if (self.get(pos).is(TokenType::LT)) {
        pos+=1;
        open+=1;
      } else if (self.get(pos).is(TokenType::GT)) {
        pos+=1;
        open-=1;
        if (open == 0) {
           return pos;
        }
      } else {
        let valid_tokens = [TokenType::IDENT, TokenType::STAR, TokenType::QUES, TokenType::LBRACKET, TokenType::RBRACKET, TokenType::COMMA, TokenType::COLON2];
        let tok = self.get(pos);
        let any = false;
        for(let i=0;i<7;++i){
          if (tok.is(valid_tokens[i])) {
            any = true;
            break;
          }
        }
        if(!any && !isPrim(tok)) return -1;
        pos+=1;
      }
    }
    return -1;
  }
  
  func isLit(t: Token *): bool{
    return t.is([TokenType::FLOAT_LIT, TokenType::INTEGER_LIT, TokenType::CHAR_LIT, TokenType::STRING_LIT, TokenType::TRUE, TokenType::TokenType::FALSE][0..6]);
  }

  func isPrim(t: Token*): bool{
    return t.is([TokenType::BOOLEAN, TokenType::VOID, TokenType::I8, TokenType::I16, TokenType::I32, TokenType::I64, TokenType::F32, TokenType::F64, TokenType::U8, TokenType::U16, TokenType::U32, TokenType::U64][0..12]);
  }
  
  func exprList(self, tt: TokenType): List<Expr>{
    let arr = List<Expr>::new();
    if(self.is(tt)) return arr;
    arr.add(self.parse_expr());
    while(self.is(TokenType::COMMA)){
      self.pop();
      arr.add(self.parse_expr());
    }
    return arr;
  }
  
  func parseLit(self): Expr{
    let kind = LitKind::INT;
    if(self.is(TokenType::INTEGER_LIT)){
      kind = LitKind::INT;
    }
    else if(self.is(TokenType::STRING_LIT)){
      kind = LitKind::STR;
    }else if(self.is(TokenType::CHAR_LIT)){
      kind = LitKind::CHAR;
    }else if(self.is(TokenType::FLOAT_LIT)){
      kind = LitKind::FLOAT;
    }else if(self.is(TokenType::FALSE) || self.is(TokenType::TRUE)){
      kind = LitKind::BOOL;
    }else{
      panic("invalid literal %s", self.peek().print().cstr());
    }
    let arr = Lexer::get_suffix();
    let val = self.popv();
    let n = self.node();
    for (let i=0;i<arr.len();++i) {
      let sf = arr[i];
      let pos = val.str().lastIndexOf(sf);
      let support_suffix = (kind is LitKind::INT || kind is LitKind::FLOAT || kind is LitKind::CHAR);
      if (pos != -1 && support_suffix) {
          //trim suffix
          val = val.substr(0, (val.len() - sf.len()) as i32).str();
          return Expr::Lit{.n, Literal{kind, val, Option<Type>::new(Type::new(sf))}};
      }
    }
    return Expr::Lit{.n, Literal{kind, val, Option<Type>::None}};
  }
  
  func name(self): String{
    if(isName(self.peek())){
      return self.popv();
    }
    panic("expected name got %s", self.peek().print().cstr());
  }
  
  func isObj(self): bool{
    if (!self.is(TokenType::IDENT)) {
        return false;
    }
    let pos = self.pos + 1;
    let ta = self.isTypeArg(pos);
    if (ta != -1) {
        pos = ta;
    }
    if (self.get(pos).is(TokenType::COLON2)) {
        pos+=1;
        if (!self.get(pos).is(TokenType::IDENT)) {
            return false;
        }
        pos+=1;
    }
    if (self.get(pos).is(TokenType::LBRACE)) {
        return true;
    }
    return false;
  }
  
  func entry(self): Entry{
    if(isName(self.peek()) && self.peek(1).is(TokenType::COLON)){
      let name = self.popv();
      self.consume(TokenType::COLON);
      let e = self.parse_expr();
      return Entry{Option::new(name), e, false};
    }
    let dot = false; 
    if(self.is(TokenType::DOT)){
      self.pop();
      dot = true;
    }
    let e = self.parse_expr();
    return Entry{Option<String>::None, e, dot};
  }

  func prim(self): Expr{
    let n = self.node();
    if(isLit(self.peek())){
      return self.parseLit();
    }else if(self.is(TokenType::LPAREN)){
        self.pop();
        let e = self.parse_expr();
        self.consume(TokenType::RPAREN);
        return Expr::Par{.n,Box::new(e)};
    }else if(self.is(TokenType::LBRACKET)){
        self.pop();
        let arr = self.exprList(TokenType::SEMI);
        let sz = Option<i32>::None;
        if(self.is(TokenType::SEMI)){
            self.pop();
            let s = self.consume(TokenType::INTEGER_LIT);
            sz = Option::new(i32::parse(s.value.str()));
        }
        self.consume(TokenType::RBRACKET);
        return Expr::Array{.n, arr, sz};
    }else if(false && self.isObj()){
      let ty = self.parse_type();
      let args = List<Entry>::new();
      self.consume(TokenType::LBRACE);
      if(!self.is(TokenType::RBRACE)){
        args.add(self.entry());
        while(self.is(TokenType::COMMA)){
          self.pop();
          args.add(self.entry());
        }
      }
      self.consume(TokenType::RBRACE);
      return Expr::Obj{.n, ty, args};
    }
    else if(isName(self.peek()) || isPrim(self.peek())){
      let nm = self.popv();
      if(self.is(TokenType::LPAREN)){
        return self.call(nm);
      }else if(self.isTypeArg(self.pos) != -1){
        let g = self.generics();
        if(self.is(TokenType::LPAREN)){
          return self.call(nm, g);
        }
        else if(self.is(TokenType::COLON2)){
          self.consume(TokenType::COLON2);
          let ty = Type::new(nm, g);
          let nm2 = self.name();
          if(self.is(TokenType::LPAREN)){
            return self.call(Expr::Type{.n, ty}, nm2, true);
          }
          return Expr::Type{.n, Type::new(ty, nm2)};
        }else {
          return Expr::Type{.n, Type::new(nm, g)};
        }
      }else if(self.is(TokenType::COLON2)){
        self.pop();
        let ty = self.parse_type();
        if(self.is(TokenType::LPAREN)){
          let ta = ty.as_simple().args.clone();
          return self.call(Expr::Type{.n, Type::new(nm)}, ty.name().clone(), true, ta);
        }else{
          return Expr::Type{.n,Type::new(Type::new(nm), ty.name().clone())};
        }
      }else{
        return Expr::Name{.n,nm};
      }
    }else if(self.is(TokenType::AND) || self.is(TokenType::BANG) || self.is(TokenType::MINUS) || self.is(TokenType::STAR) || self.is(TokenType::PLUSPLUS) || self.is(TokenType::MINUSMINUS)){
      let op = self.popv();
      let e = self.prim2();
      return Expr::Unary{.n,op, Box::new(e)};
    }
    panic("invalid expr %s", self.peek().print().cstr());
  }
  
  //Type "{" entries* "}" | "." name ( args ) | "." name | "[" expr (".." expr)? "]"
  func prim2(self): Expr{
    let e = self.prim();
    if(self.is(TokenType::LBRACE)){
      let ty = Option<Type>::None; 
      if let Expr::Name(nm)=(e){
        ty = Option::new(Type::new(nm));
      }else if let Expr::Type(t)=(e){
        ty = Option::new(t);
      }else panic("was expecting name got %s", Fmt::str(&e).cstr());
      let args = List<Entry>::new();
      self.consume(TokenType::LBRACE);
      if(!self.is(TokenType::RBRACE)){
        args.add(self.entry());
        while(self.is(TokenType::COMMA)){
          self.pop();
          args.add(self.entry());
        }
      }
      self.consume(TokenType::RBRACE);
      let n = self.node();
      e = Expr::Obj{.n,ty.unwrap(), args};
    }
    while(self.is(TokenType::DOT) || self.is(TokenType::LBRACKET)){
      if(self.is(TokenType::DOT)){
        self.pop();
        let nm = self.name();
        if(self.is(TokenType::LPAREN)){
          e = self.call(e, nm, false);
        }else{
          let n = self.node();
          e = Expr::Access{.n,Box::new(e), nm}; 
        }
      }else{
          self.pop();
          let idx = self.parse_expr();
          let idx2 = Option<Box<Expr>>::None;
          if(self.is(TokenType::DOTDOT)){
              self.pop();
              idx2 = Option::new(Box::new(self.parse_expr()));
          }
          self.consume(TokenType::RBRACKET);
          let n = self.node();
          e = Expr::ArrAccess{.n,ArrAccess{Box::new(e), Box::new(idx), idx2}}; 
      }
    }
    return e; 
  }
  
  func as_is(self): Expr{
    let e = self.prim2();
    let n = self.node();
    if(self.is(TokenType::AS)){
      self.pop();
      let t = self.parse_type();
      e = Expr::As{.n,Box::new(e), t};
    }
    if(self.is(TokenType::IS)){
      self.pop();
      let rhs = self.prim2();
      e = Expr::Is{.n,Box::new(e), Box::new(rhs)};
    }
    return e;
  }
  
  func expr_level(self, prec: i32): Expr{
    if(prec == 11) return self.as_is();
    let e = self.expr_level(prec + 1);
    while(Parser::get_prec(&self.peek().type) == prec){
      let op = self.popv();
      if(op.eq(">") && self.is(TokenType::GT)){
        self.pop();
        op.append(">");
      }
      let r = self.expr_level(prec + 1);
      let n = self.node();
      e = Expr::Infix{.n, op, Box::new(e), Box::new(r)};
    }
    return e;
  }
  
  func get_prec(tt: TokenType*): i32{
    if(tt is TokenType::EQ || tt is TokenType::PLUSEQ || tt is TokenType::MINUSEQ || tt is TokenType::MULEQ || tt is TokenType::DIVEQ || tt is TokenType::PERCENTEQ || tt is TokenType::ANDEQ || tt is TokenType::OREQ || tt is TokenType::POWEQ || tt is TokenType::LTLTEQ || tt is TokenType::GTGTEQ) return 0;
    if(tt is TokenType::OROR) return 1;
    if(tt is TokenType::ANDAND) return 2;
    if(tt is TokenType::OR) return 3;
    if(tt is TokenType::POW) return 4;
    if(tt is TokenType::AND) return 5;
    if(tt is TokenType::EQEQ) return 6;
    if(tt is TokenType::NOTEQ) return 6;
    if(tt is TokenType::LT || tt is TokenType::GT || tt is TokenType::LTEQ || tt is TokenType::GTEQ) return 7;
    if(tt is TokenType::LTLT) return 8;
    if(tt is TokenType::GTGT) return 8;
    if(tt is TokenType::PLUS) return 9;
    if(tt is TokenType::MINUS) return 9;
    if(tt is TokenType::STAR) return 10;
    if(tt is TokenType::DIV) return 10;
    if(tt is TokenType::PERCENT) return 10;
    //panic("is op %s", Fmt::str(tt).cstr());
    return -1;
  }
  
  func parse_expr(self): Expr{
    return self.expr_level(0);
  }

  func call(self, scp: Expr, nm: String, is_static: bool): Expr{
    self.consume(TokenType::LPAREN);
    let args = self.exprList(TokenType::RPAREN);
    self.consume(TokenType::RPAREN);
    return self.newCall(scp, nm, args, is_static);
  }
  func call(self, scp: Expr, nm: String, is_static: bool, ta: List<Type>): Expr{
    self.consume(TokenType::LPAREN);
    let args = self.exprList(TokenType::RPAREN);
    self.consume(TokenType::RPAREN);
    return self.newCall(scp, nm, args, is_static, ta);
  }
  func call(self, nm: String): Expr{
    self.consume(TokenType::LPAREN);
    let args = self.exprList(TokenType::RPAREN);
    self.consume(TokenType::RPAREN);
    return self.newCall(nm, args);
  }
  func call(self, nm: String, g: List<Type>): Expr{
    self.consume(TokenType::LPAREN);
    let args = self.exprList(TokenType::RPAREN);
    self.consume(TokenType::RPAREN);
    return self.newCall(nm, g, args);
  }
  
  func newCall(self,name: String, args: List<Expr>): Expr{
    return self.newCall(name, List<Type>::new(), args);
  }
  func newCall(self, name: String, g: List<Type>, args: List<Expr>): Expr{
    let n = self.node();
    return Expr::Call{.n,Call{Option<Box<Expr>>::None, name, g, args, false}};
  }
  func newCall(self, scp: Expr, name: String, args: List<Expr>, is_static: bool): Expr{
    let n = self.node();
    return Expr::Call{.n,Call{Option::new(Box::new(scp)), name, List<Type>::new(), args, is_static}};
  }
  func newCall(self, scp: Expr, name: String, args: List<Expr>, is_static: bool, ta: List<Type>): Expr{
    let n = self.node();
    return Expr::Call{.n,Call{Option::new(Box::new(scp)), name, ta, args, is_static}};
  }
}

func dump(e: Expr*){
  let f = Fmt::new();
  e.debug(&f);
  f.buf.dump();
}
func dump(e: Stmt*){
  let f = Fmt::new();
  e.debug(&f);
  f.buf.dump();
}