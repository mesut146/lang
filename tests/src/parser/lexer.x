import parser/token
import std/map
import std/libc
import std/io

class Lexer{
  path: String;
  buf: String;
  pos: i32;
  line: i32;
  ops: Map<str, TokenType>;
}

impl i8{
  func in(self, a: i32, b: i32): bool{ return self <= b && self >= a; }
  
  func is_letter(self): bool{
    return self.in('a', 'z') || self.in('A', 'Z');
  }
  func is_digit(self): bool{
    return self.in('0', '9');
  }
  func is_alpha(self): bool{
    return self.is_letter() || self.is_digit();
  }
  func is_hex(self): bool{
    return self.in('a', 'f') || self.in('A', 'F') || self.is_digit();
  }
}

impl Lexer{
  func new(path: String): Lexer{
    let s = String::new(read_bytes(path.str()));
    return Lexer{path: path, buf: s, pos: 0, line: 1, ops: make_ops()};
  }
  
  func peek(self): i8{
    return self.buf.get(self.pos);
  }
  
  func peek(self, off: i32): i8{
    return self.buf.get(self.pos + off);
  }
  
  func read(self): i8{
    let res = self.buf.get(self.pos);
    self.pos += 1;
    return res;
  }
  
  func has(self): bool{
    return self.pos < self.buf.len();
  }
  
  func str(self, a: i32, b: i32): str{
    return self.buf.str().substr(a, b);
  }
  
  func line_comment(self): Token{
    let start = self.pos;
    self.pos += 2;
    let c = self.peek();
    while (c != '\n' && c != '\0') {
        self.pos+=1;
        c = self.peek();
    }
    return Token::new(TokenType::COMMENT, self.str(start, self.pos));
  }
  
  func checkEscape(c: i8): i32 {
    if (c == 'n') return '\n';
    if (c == 'r') return '\r';
    if (c == 't') return '\t';
    if (c == '\\') return '\\';
    if (c == '"') return '"';
    if (c == '\'') return '\'';
    if (c == '0') return '\0';
    panic("invalid escape: %c", c);
  }
  
  func make_ops(): Map<str, TokenType>{
    let ops = Map<str, TokenType>::new();
    ops.add("{", TokenType::LBRACE);
    ops.add("}", TokenType::RBRACE);
    ops.add("(", TokenType::LPAREN);
    ops.add(")", TokenType::RPAREN);
    ops.add("[", TokenType::LBRACKET);
    ops.add("]", TokenType::RBRACKET);
    ops.add("/", TokenType::DIV);
    ops.add(":", TokenType::COLON);
    ops.add("::", TokenType::COLON2);
    ops.add(";", TokenType::SEMI);
    ops.add(",", TokenType::COMMA);
    ops.add(".", TokenType::DOT);
    ops.add("<", TokenType::LT);
    ops.add(">", TokenType::GT);
    ops.add("=", TokenType::EQ);
    ops.add("+=", TokenType::PLUSEQ);
    ops.add("-=", TokenType::MINUSEQ);
    ops.add("*=", TokenType::MULEQ);
    ops.add("/=", TokenType::DIVEQ);
    ops.add("^=", TokenType::POWEQ);
    ops.add("+", TokenType::PLUS);
    ops.add("-", TokenType::MINUS);
    ops.add("*", TokenType::STAR);
    ops.add("/", TokenType::DIV);
    ops.add("%", TokenType::PERCENT);
    ops.add("^", TokenType::POW);
    ops.add("~", TokenType::TILDE);
    ops.add("&", TokenType::AND);
    ops.add("|", TokenType::OR);
    ops.add("&&", TokenType::ANDAND);
    ops.add("||", TokenType::OROR);
    ops.add("==", TokenType::EQEQ);
    ops.add("!=", TokenType::NOTEQ);
    ops.add("<=", TokenType::LTEQ);
    ops.add(">=", TokenType::GTEQ);
    ops.add("!", TokenType::BANG);
    ops.add("#", TokenType::HASH);
    ops.add("++", TokenType::PLUSPLUS);
    ops.add("..", TokenType::DOTDOT);
    ops.add("<<", TokenType::LTLT);
    return ops;
  }
  
  func kw(s: str): TokenType{
    if(s.eq("assert")) return TokenType::ASSERT_KW;
    if(s.eq("class")) return TokenType::CLASS;
    if(s.eq("struct")) return TokenType::STRUCT;
    if(s.eq("enum")) return TokenType::ENUM;
    if(s.eq("trait")) return TokenType::TRAIT;
    if(s.eq("impl")) return TokenType::IMPL;
    if(s.eq("type")) return TokenType::TYPE;
    if(s.eq("extern")) return TokenType::EXTERN;
    if(s.eq("virtual")) return TokenType::VIRTUAL;
    if(s.eq("static")) return TokenType::STATIC;
    if(s.eq("bool")) return TokenType::BOOLEAN;
    if(s.eq("import")) return TokenType::IMPORT;
    if(s.eq("true")) return TokenType::TRUE;
    if(s.eq("false")) return TokenType::FALSE;
    if(s.eq("i8")) return TokenType::I8;
    if(s.eq("i16")) return TokenType::I16;
    if(s.eq("i32")) return TokenType::I32;
    if(s.eq("i64")) return TokenType::I64;
    if(s.eq("f32")) return TokenType::F32;
    if(s.eq("f64")) return TokenType::F64;
    if(s.eq("null")) return TokenType::NULL_LIT;
    if(s.eq("as")) return TokenType::AS;
    if(s.eq("is")) return TokenType::IS;
    if(s.eq("from")) return TokenType::FROM;
    if(s.eq("return")) return TokenType::RETURN;
    if(s.eq("continue")) return TokenType::CONTINUE;
    if(s.eq("if")) return TokenType::IF;
    if(s.eq("else")) return TokenType::ELSE;
    if(s.eq("for")) return TokenType::FOR;
    if(s.eq("while")) return TokenType::WHILE;
    if(s.eq("do")) return TokenType::DO;
    if(s.eq("break")) return TokenType::BREAK;
    if(s.eq("func")) return TokenType::FUNC;
    if(s.eq("let")) return TokenType::LET;
    if(s.eq("new")) return TokenType::NEW;
    if(s.eq("match")) return TokenType::MATCH;
    if(s.eq("const")) return TokenType::CONST;
    return TokenType::EOF_;
  }
  
  func read_op(self): Token{
    //can be length of 1 to 3
    for (let i = 3; i > 0; i-=1) {
        if(self.pos + i > self.buf.len()){
          continue;
        }
        let s = self.str(self.pos, self.pos + i); 
        let it = self.ops.get(s);
        if (it.is_some()) {
            self.pos += i;
            let tok = it.unwrap(); 
            return Token::new(tok, s);
        }
    }
    //never
    panic("readOp() failed with buffer: %c", self.peek());
}

  func skip_ws(self){
   let c = self.peek();
   while(c ==' ' || c == '\r' || c == '\n' || c == '\t'){
      self.pos += 1;
      if(c == '\n'){
        self.line+=1;
      }else if(c == '\r'){
        self.line+=1;
        if (self.has() && self.peek() == '\n') {
          self.pos+=1;
        }
      }
      if(!self.has()) break;
      c = self.peek();
    }
  }
  
  func next(self): Token{
    let start = self.pos;
    let res = self.next0();
    res.line = self.line;
    res.start = start;
    res.end = self.pos;
    return res;
  }
  
  func block_comment(self): Token{
    let start = self.pos;
    self.pos += 2;
    while (self.has()) {
      if (self.peek() == '*') {
        self.pos+=1;
        if (self.has() && self.peek() == '/') {
          self.pos+=1;
          return Token::new(TokenType::COMMENT, self.str(start, self.pos));                        
        }
      } else {
        if (self.peek() == '\r') {
          self.pos+=1;
          self.line+=1;
          if (self.peek() == '\n') {
           self.pos+=1;
          }
        } else if (self.peek() == '\n') {
          self.pos+=1;
          self.line+=1;
        } else {
          self.pos+=1;
        }
      }
    }            
    panic("unclosed block comment at line %d" , self.line);
  }
  
  func next0(self): Token{
    if(self.pos == self.buf.len()) return Token::new(TokenType::EOF_);
    if(self.peek() == 0) return Token::new(TokenType::EOF_);
    self.skip_ws();
    if(self.pos == self.buf.len()) return Token::new(TokenType::EOF_);
    let c = self.peek();
    let start = self.pos;
    if(c.is_letter() || c == '_'){
      return self.read_ident();
    }
    if(c.is_digit() || c == '-' && self.peek(1).is_digit()){
      return self.read_number();
    }
    if (c == '/') {
        let c2 = self.peek(1);
        if (c2 == '/') {
            return self.line_comment();
        } else if (c2 == '*') {
            return self.block_comment();
        } else {
            return self.read_op();
        }
    }
    if (c == '\'' || c == '"') {
        let open = c;
        let type = TokenType::STRING_LIT;
        if(c == '\'') type = TokenType::CHAR_LIT;
        let s = String::new();
        s.append(c);
        self.pos+=1;
        while (self.pos < self.buf.len()) {
            c = self.read();
            if (c == '\\') {
                s.append("\\");
                s.append(self.peek());
                self.pos+=1;
            } else if (c == open) {
                s.append(c);
                return Token::new(type, s);
            } else {
                s.append(c);
            }
        }
        panic("unterminated string literal");
    }
    let os = String::new();
    os.append(c);
    if(self.ops.get(os.str()).is_some()){
      return self.read_op();
    }
    panic("unexpected char: %c(%d) at %d" , c, c, start);
  }
  
  func read_ident(self): Token {
    let a = self.pos;
    self.pos+= 1;
    let c = self.peek();
    while (c.is_letter() || c == '_' || c.is_digit()) {
        self.pos+=1;
        c = self.peek();
    }
    let s = self.str(a, self.pos);
    let type = kw(s);
    if (type is TokenType::EOF_) {
        type = TokenType::IDENT;
    }
    return Token::new(type, s);
  }
  
  //[0-9] ('_'? [0-9])* ('.' [0-9]+)? ('_' suffix)?
  func read_number(self):Token {
    let dot = false;
    let start = self.pos;
    if(self.peek() == '0' && self.peek(1) == 'x'){
      self.pos+=2;
      while(self.peek().is_hex()){
        self.pos+=1;
      }
      let type = TokenType::INTEGER_LIT;
      return Token::new(type, self.str(start, self.pos));
    }
    self.pos += 1;
    while (true){
      let c = self.peek();
      if(c.is_digit()){
        self.pos+=1;
      }else if(c == '_' && self.peek(1).is_digit()){
        self.pos+=2;
      }else break;
    }
    if(self.peek() == '.' && self.peek(1).is_digit()){
      dot = true;
      self.pos += 2;
      while (self.has() && self.peek().is_digit()) {
        self.pos += 1;
      }
    }
    let mustSuffix = false;
    if(self.peek()=='_'){
      self.pos+=1;
      mustSuffix = true; 
    }
    let suffixes = ["i8", "i16", "i32", "i64", "f32", "f64"];
    let has = false;
    for (let i =0;i < 6;++i) {
      let sf = suffixes[i];
      if (self.str(self.pos, self.pos + sf.len()).eq(sf)) {
        self.pos += sf.len();
        has = true;
        break;
      }
    }
    if(mustSuffix && !has) panic("expected literal suffix");
    let type = TokenType::INTEGER_LIT;
    if(dot) type = TokenType::FLOAT_LIT;
    return Token::new(type, self.str(start, self.pos));
  }
  
}
