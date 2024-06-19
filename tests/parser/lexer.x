import parser/token
import std/map
import std/libc
import std/io

struct Lexer{
  path: String;
  buf: String;
  pos: i32;
  line: i32;
  single_line: i32;//macro code is single lined
  ops: Map<str, TokenType>;
}

impl i8{
  func in(self, a: i32, b: i32): bool{ return *self <= b && *self >= a; }
  
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
  func from_path(path: String): Lexer{
    let s = read_string(path.str());
    return Lexer{path: path, buf: s, pos: 0, line: 1, single_line: -1, ops: make_ops()};
  }
  func from_string(path: String, buf: String, line: i32): Lexer{
    return Lexer{path: path, buf: buf, pos: 0, line: 1, single_line: line, ops: make_ops()};
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
    return self.has(1);
  } 

  func has(self, cnt: i32): bool{
    return self.pos + cnt - 1 < self.buf.len();
  }
  
  func str(self, a: i32, b: i32): str{
    return self.buf.str().substr(a, b);
  }

  func line(self): i32{
    if(self.single_line == -1){
      return self.line;
    }
    return self.single_line;
  }

  func get_line(buf: str, line: i32): str{
    let cur_line = 1;
    let pos = 0;
    while(pos < buf.len()){
      if(cur_line == line){
        let end = buf.indexOf("\n", pos);
        if(end == -1){
          end = buf.len() as i32;
        }
        return buf.substr(pos, end);
      }else{
        let i = buf.indexOf("\n", pos);
        if(i == -1){
    
        }else{
          cur_line += 1;
          pos = i + 1;
        }
      }
    }
    panic("not possible");
  }

  func err(self, msg: str){
    print("in file {}:{} `{}`\n", &self.path, self.line(), get_line(self.buf.str(), self.line()));
    panic("{}", msg);
  }
  func err(self, msg: String){
    self.err(msg.str());
  }
  
  func line_comment(self): Token{
    let start = self.pos;
    self.pos += 2;
    while(self.has()){
      let c = self.peek();
      if (c != '\n' && c != '\0') {
        self.pos += 1;
      }else{
        break;
      }
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
    panic("invalid escape: {}", c);
  }
  
  func make_ops(): Map<str, TokenType>{
    let ops = Map<str, TokenType>::new();
    ops.add("{", TokenType::LBRACE);
    ops.add("}", TokenType::RBRACE);
    ops.add("(", TokenType::LPAREN);
    ops.add(")", TokenType::RPAREN);
    ops.add("[", TokenType::LBRACKET);
    ops.add("]", TokenType::RBRACKET);
    ops.add(":", TokenType::COLON);
    ops.add("::", TokenType::COLON2);
    ops.add(";", TokenType::SEMI);
    ops.add(",", TokenType::COMMA);
    ops.add(".", TokenType::DOT);
    ops.add("<", TokenType::LT);
    ops.add(">", TokenType::GT);
    ops.add("<<", TokenType::LTLT);
    //ops.add(">>", TokenType::GTGT);
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
    ops.add("--", TokenType::MINUSMINUS);
    ops.add("..", TokenType::DOTDOT);
    return ops;
  }
  
  func kw(s: str): TokenType{
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
        let it = self.ops.get_ptr(&s);
        if (it.is_some()) {
            self.pos += i;
            let tok = it.unwrap(); 
            return Token::new(*tok, s);
        }
    }
    //never
    panic("readOp() failed with buffer: {}", self.peek());
}

  func skip_ws(self){
   let c = self.peek();
   while(c ==' ' || c == '\r' || c == '\n' || c == '\t'){
      self.pos += 1;
      if(c == '\n'){
        self.line += 1;
      }else if(c == '\r'){
        self.line+=1;
        if (self.has() && self.peek() == '\n') {
          self.pos += 1;
        }
      }
      if(!self.has()) break;
      c = self.peek();
    }
  }
  
  func next(self): Token{
    let start = self.pos;
    let res = self.next0();
    res.line = self.line();
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
          self.line += 1;
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
    panic("unclosed block comment at line {}" , self.line());
  }

  func read_string(self): Token{
    let c = self.peek();
    let open = c;
    let kind = TokenType::STRING_LIT;
    if(c == '\''){
      kind = TokenType::CHAR_LIT;
    }
    let str = String::new();
    //s.append(c);
    self.pos += 1;
    while (self.pos < self.buf.len()) {
        c = self.read();
        if (c == '\\') {
            //s.append("\\");
            str.append(checkEscape(self.peek()) as i8);
            self.pos += 1;
        } else if (c == open) {
            //s.append(c);
            return Token::new(kind, str);
        } else {
          str.append(c);
        }
    }
    self.err("unterminated string literal");
    panic("");
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
    if(c.is_digit()){
      return self.read_number();
    }
    if(c == '-' && self.has(2)){
      let peeked = self.peek(1);
      if(peeked.is_digit()){
        return self.read_number();
      }
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
        return self.read_string();
    }
    let os = String::new();
    os.append(c);
    let oss = os.str();
    if(self.ops.get_ptr(&oss).is_some()){
      os.drop();
      return self.read_op();
    }
    os.drop();
    panic("in file {}\nunexpected char: {}({}) at {}", &self.path, c, c, start);
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
    let start = self.pos;
    let off = 0;
    if(self.peek() == '-'){
      self.pos += 1;
    }
    if(self.peek(0) == '0' && self.peek(1) == 'x'){
      self.pos += 2;
      while(true){
        let c = self.peek();
        if(!c.is_hex()) break;
        self.pos += 1;
      }
      let type = TokenType::INTEGER_LIT;
      return Token::new(type, self.str(start, self.pos));
    }
    self.pos += 1;
    while (true){
      let c = self.peek();
      if(c.is_digit()){
        self.pos += 1;
      }else if(c == '_' && self.has(2) && self.peek(1).is_digit()){
        self.pos+=2;
      }else break;
    }
    let dot = false;
    if(self.peek() == '.' && self.has(2) && self.peek(1).is_digit()){
      dot = true;
      self.pos += 2;
      while (self.has()) {
        let c = self.peek();
        if(!c.is_digit()) break;
        self.pos += 1;
      }
    }
    let mustSuffix = false;
    if(self.peek() == '_'){
      self.pos += 1;
      mustSuffix = true; 
    }
    let suffixes = get_suffix();
    let has = false;
    for (let i = 0;i < suffixes.len();++i) {
      let sf = suffixes[i];
      if (self.has(sf.len()) && self.str(self.pos, self.pos + sf.len()).eq(sf)) {
        self.pos += sf.len();
        has = true;
        break;
      }
    }
    if(mustSuffix && !has) self.err(format("expected literal suffix got: {}", self.peek()));
    let type = TokenType::INTEGER_LIT;
    if(dot) type = TokenType::FLOAT_LIT;
    return Token::new(type, self.str(start, self.pos));
  }

  func get_suffix(): [str; 10]{
    return ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64"];
  }
  
}
