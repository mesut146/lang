import std/hashmap
import std/libc
import std/io
import std/fs
import parser/token
import parser/utils

static lexer_keywords = make_keywords();
static lexer_ops = make_ops();

func make_keywords(): HashMap<str, TokenType>{
  let map = HashMap<str, TokenType>::new(55);
  map.insert("as", TokenType::AS);
  map.insert("bool", TokenType::BOOLEAN);
  map.insert("break",  TokenType::BREAK);
  map.insert("const",  TokenType::CONST);
  map.insert("continue", TokenType::CONTINUE);
  map.insert("do",  TokenType::DO);
  map.insert("else",  TokenType::ELSE);
  map.insert("enum", TokenType::ENUM);
  map.insert("extern", TokenType::EXTERN);
  map.insert("f32", TokenType::F32);
  map.insert("f64", TokenType::F64);
  map.insert("false",  TokenType::FALSE);
  map.insert("for",  TokenType::FOR);
  map.insert("func",  TokenType::FUNC);
  map.insert("i8", TokenType::I8);
  map.insert("i16", TokenType::I16);
  map.insert("i32", TokenType::I32);
  map.insert("i64", TokenType::I64);
  map.insert("if",  TokenType::IF);
  map.insert("impl", TokenType::IMPL);
  map.insert("import", TokenType::IMPORT);
  map.insert("is", TokenType::IS);
  map.insert("let", TokenType::LET);
  map.insert("match",  TokenType::MATCH);
  map.insert("mod", TokenType::MOD);
  map.insert("null", TokenType::NULL_LIT);
  map.insert("return", TokenType::RETURN);
  map.insert("static", TokenType::STATIC);
  map.insert("struct", TokenType::STRUCT);
  map.insert("trait", TokenType::TRAIT);
  map.insert("true",  TokenType::TRUE);
  map.insert("type", TokenType::TYPE);
  map.insert("u8", TokenType::U8);
  map.insert("u16", TokenType::U16);
  map.insert("u32", TokenType::U32);
  map.insert("u64", TokenType::U64);
  map.insert("virtual", TokenType::VIRTUAL);
  map.insert("while",  TokenType::WHILE);
  return map;
}

func make_ops(): HashMap<str, TokenType>{
  let map = HashMap<str, TokenType>::new(56);
  map.add("{", TokenType::LBRACE);
  map.add("}", TokenType::RBRACE);
  map.add("(", TokenType::LPAREN);
  map.add(")", TokenType::RPAREN);
  map.add("[", TokenType::LBRACKET);
  map.add("]", TokenType::RBRACKET);
  map.add(":", TokenType::COLON);
  map.add("::", TokenType::COLON2);
  map.add(";", TokenType::SEMI);
  map.add(",", TokenType::COMMA);
  map.add(".", TokenType::DOT);
  map.add("<", TokenType::LT);
  map.add(">", TokenType::GT);
  map.add("<<", TokenType::LTLT);
  //map.add(">>", TokenType::GTGT);
  map.add("=", TokenType::EQ);
  map.add("+=", TokenType::PLUSEQ);
  map.add("-=", TokenType::MINUSEQ);
  map.add("*=", TokenType::MULEQ);
  map.add("/=", TokenType::DIVEQ);
  map.add("^=", TokenType::POWEQ);
  map.add("+", TokenType::PLUS);
  map.add("-", TokenType::MINUS);
  map.add("*", TokenType::STAR);
  map.add("/", TokenType::DIV);
  map.add("%", TokenType::PERCENT);
  map.add("?", TokenType::QUES);
  map.add("^", TokenType::POW);
  map.add("~", TokenType::TILDE);
  map.add("&", TokenType::AND);
  map.add("|", TokenType::OR);
  map.add("&&", TokenType::ANDAND);
  map.add("||", TokenType::OROR);
  map.add("==", TokenType::EQEQ);
  map.add("!=", TokenType::NOTEQ);
  map.add("<=", TokenType::LTEQ);
  map.add(">=", TokenType::GTEQ);
  map.add("!", TokenType::BANG);
  map.add("#", TokenType::HASH);
  map.add("++", TokenType::PLUSPLUS);
  map.add("--", TokenType::MINUSMINUS);
  map.add("..", TokenType::DOTDOT);
  map.add("=>", TokenType::ARROW);
  return map;
}

struct Lexer{
  path: String;
  buf: String;
  pos: i32;
  line: i32;
  single_line: i32;//macro code is single lined
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
    let s = File::read_string(path.str())?;
    return Lexer{path: path, buf: s, pos: 0, line: 1, single_line: -1};
  }
  func from_string(path: String, buf: String, line: i32): Lexer{
    return Lexer{path: path, buf: buf, pos: 0, line: 1, single_line: line};
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

  func make_err_header(self, print_line: bool): String{
    if(print_line){
      return format("lexer error in file {}:{} `{}`", &self.path, self.line(), get_line(self.buf.str(), self.line()));
    }else{
      return format("lexer error in file {}:{}", &self.path, self.line());
    }
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
  
  func checkEscape(c: i8): Result<i32, String> {
    if (c == 'n') return Result<i32, String>::ok('\n');
    if (c == 'r') return Result<i32, String>::ok('\r');
    if (c == 't') return Result<i32, String>::ok('\t');
    if (c == '\\') return Result<i32, String>::ok('\\');
    if (c == '"') return Result<i32, String>::ok('"');
    if (c == '\'') return Result<i32, String>::ok('\'');
    if (c == '0') return Result<i32, String>::ok('\0');
    return Result<i32, String>::err(format("invalid escape: {} val: {}", c, c as i32));
  }
  
  func kw(s: str): TokenType{
    let opt = lexer_keywords.get(&s);
    /*if let Option::Some(val) = opt{

    }*/
    if(opt.is_some()) return *opt.unwrap();
    return TokenType::EOF_;
  }
  
  func read_op(self): Result<Token, String>{
    //can be length of 1 to 3
    for (let i = 3; i > 0; i-=1) {
        if(self.pos + i > self.buf.len()){
          continue;
        }
        let s = self.str(self.pos, self.pos + i); 
        let it = lexer_ops.get(&s);
        if (it.is_some()) {
            self.pos += i;
            let tok = it.unwrap(); 
            return Result<Token, String>::ok(Token::new(*tok, s));
        }
    }
    //never
    return Result<Token, String>::err(format("readOp() failed with buffer: {:?}", self.peek()));
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
    //todo err propagate
    let tmp = self.next0();
    if(tmp.is_err()){
      let err = self.make_err_header(true);
      err.append("\n");
      err.append(tmp.get_err());
      panic("{}", err);
    }
    let res = tmp.unwrap();
    res.line = self.line();
    res.start = start;
    res.end = self.pos;
    return res;
  }

  func next0(self): Result<Token, String>{
    if(self.pos == self.buf.len()) return Result<Token, String>::ok(Token::new(TokenType::EOF_));
    if(self.peek() == 0) return Result<Token, String>::ok(Token::new(TokenType::EOF_));
    self.skip_ws();
    if(self.pos == self.buf.len()) return Result<Token, String>::ok(Token::new(TokenType::EOF_));
    let c = self.peek();
    let start = self.pos;
    if(c.is_letter() || c == '_'){
      return Result<Token, String>::ok(self.read_ident());
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
            return Result<Token, String>::ok(self.line_comment());
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
    if(lexer_ops.get(&oss).is_some()){
      os.drop();
      return self.read_op();
    }
    os.drop();
    let err = String::new();
    if(self.single_line != -1){
      err.append("buf='");
      err.append(&self.buf);
      err.append("'\n");
    }
    return Result<Token, String>::err(format("unexpected char: '{}' val: {} pos: {}", c, c as i32, start));
  }
  
  func block_comment(self): Result<Token, String>{
    let start = self.pos;
    self.pos += 2;
    while (self.has()) {
      if (self.peek() == '*') {
        self.pos += 1;
        if (self.has() && self.peek() == '/') {
          self.pos += 1;
          return Result<Token, String>::ok(Token::new(TokenType::COMMENT, self.str(start, self.pos)));
        }
      }
      else if (self.peek() == '\r') {
        self.pos += 1;
        self.line += 1;
        if (self.has() && self.peek() == '\n') {
          self.pos += 1;
        }
      } else if (self.peek() == '\n') {
        self.pos += 1;
        self.line += 1;
      } else {
        self.pos += 1;
      }
    }            
    return Result<Token, String>::err(format("unclosed block comment at line {}" , self.line()));
  }

  func read_string(self): Result<Token, String>{
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
            let escp = checkEscape(self.peek());
            str.append(escp.unwrap() as i8);
            self.pos += 1;
        } else if (c == open) {
            //s.append(c);
            return Result<Token, String>::ok(Token::new(kind, str));
        } else {
          str.append(c);
        }
    }
    return Result<Token, String>::err("unterminated string literal".owned());
  }
  
  func read_ident(self): Token {
    let start = self.pos;
    self.pos += 1;
    while (self.has()) {
      let c = self.peek();
      if(c.is_letter() || c == '_' || c.is_digit()){
        self.pos += 1;
      }else{
        break;
      }
    }
    let val = self.str(start, self.pos);
    let ty = kw(val);
    if (ty is TokenType::EOF_) {
        ty = TokenType::IDENT;
    }
    return Token::new(ty, val);
  }
  
  //[0-9] ('_'? [0-9])* ('.' [0-9]+)? ('_' suffix)?
  func read_number(self): Result<Token, String> {
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
      return Result<Token, String>::ok(Token::new(type, self.str(start, self.pos)));
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
    if(mustSuffix && !has){
      return Result<Token, String>::err(format("expected literal suffix got: {}", self.peek()));
    }
    let type = TokenType::INTEGER_LIT;
    if(dot) type = TokenType::FLOAT_LIT;
    return Result<Token, String>::ok(Token::new(type, self.str(start, self.pos)));
  }

  func get_suffix(): [str; 10]{
    return ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64"];
  }
  
}
