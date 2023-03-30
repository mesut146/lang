import parser/token
import String
import str
import List
import libc
import Option
import map

class Lexer{
  path: str;
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
}

impl Lexer{
  func new(path: str): Lexer{
    let s = String{read_bytes(path)};
    return Lexer{path: path, buf: s, pos: 0, line: 1, ops: make_ops()};
  }
  func peek(self): i8{
    return self.buf.get(self.pos);
  }
  func read(self): i8{
    let res = self.buf.get(self.pos);
    self.pos+=1;
    return res;
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
    if (c == '"') return '"';
    if (c == '\'') return '\'';
    panic("invalid escape: %c", c);
  }
  
  func make_ops(): Map<str, TokenType>{
    let ops = Map<str, TokenType>::new();
    ops.add("{", TokenType::LBRACE);
    ops.add("}", TokenType::RBRACE);
    ops.add("/", TokenType::DIV);
    return ops;
  }
  
  func read_op(self): Token{
    //let s = self.str(self.pos, self.pos + 3);
    //can be length of 1 to 3
    for (let i = 3; i > 0; i-=1) {
        let s = self.str(self.pos, self.pos + i); 
        let it = self.ops.get(s);
        if (it.is_some()) {
            self.pos += i;
            print("found op %d\n", it.unwrap().index);
            s.dump();
            return Token::new(it.unwrap(), s);
        }
    }
    //never
    panic("readOp() failed with buffer: %c", self.peek());
}
  
  func next(self): Token{
    if(self.pos == self.buf.len()) return Token::new(TokenType::EOF_);
    let c = self.peek();
    if(c == 0) return Token::new(TokenType::EOF_);
    if(c ==' ' || c == '\r' || c == '\n' || c == '\t'){
      self.pos += 1;
      if(c == '\n'){
        self.line+=1;
      }else if(c == '\r'){
        self.line+=1;
        if (self.pos < self.buf.len() && self.peek() == '\n') {
          self.pos+=1;
        }
      }
      return self.next();
    }
    let start = self.pos;
    if(c.is_letter() || c == '_'){
      return self.read_ident();
    }
    if(c.is_digit()){
      return self.read_number();
    }
    if (c == '/') {
        print("saw / pos=%d\n", self.pos);
        let c2 = self.buf.get(self.pos + 1);
        if (c2 == '/') {
            return self.line_comment();
        } else if (c2 == '*') {
            self.pos += 2;
            while (self.pos < self.buf.len()) {
                if (self.buf.get(self.pos) == '*') {
                    self.pos+=1;
                    if (self.pos < self.buf.len() && self.buf.get(self.pos) == '/') {
                        self.pos+=1;
                        return Token::new(TokenType::COMMENT, self.str(start, self.pos));                        
                    }
                } else {
                    if (self.buf.get(self.pos) == '\r') {
                        self.pos+=1;
                        self.line+=1;
                        if (self.buf.get(self.pos) == '\n') {
                            self.pos+=1;
                        }
                    } else if (self.buf.get(self.pos) == '\n') {
                        self.pos+=1;
                        self.line+=1;
                    } else {
                        self.pos+=1;
                    }
                }
            }            
            panic("unclosed block comment at line %d" , self.line);
        } else {
        print("before op / pos=%d\n", self.pos);
            return self.read_op();
        }
    }
    if (c == '\'') {
        self.pos+=1;
        while (self.pos < self.buf.len()) {
            c = self.read();
            if (c == '\\') {
                self.pos+=1;
            } else if (c == '\'') {
                return Token::new(TokenType::CHAR_LIT, self.str(start, self.pos));
            }
        }
        panic("unterminated char literal");
    }
    if (c == '"') {
        let s = String::new();
        s.append(c);
        self.pos+=1;
        while (self.pos < self.buf.len()) {
            c = self.read();
            if (c == '\\') {
                let esc = checkEscape(self.peek()) as i8;
                s.append(esc);
                self.pos+=1;
            } else if (c == '"') {
                s.append(c);
                return Token::new(TokenType::STRING_LIT, s);
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
    panic("unexpected char: %c(%d)" , c, c);
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
    let res = Token::new(type, s);
    //let res = Token{String::new(s), type, 0, 0, 0};
    return res;
  }
  
  func read_number(self):Token {
    let dot = false;
    let start = self.pos;
    self.pos+=1;
    let c = self.peek();
    while (c.is_digit() || (c == '.' && self.buf.get(self.pos + 1).is_digit())) {
        if(c == '.') dot = true;
        self.pos+=1;
        c = self.peek();
    }
    let suffixes = ["i8", "i16", "i32", "i64", "f32", "f64"];
    for (let i =0;i < 6;++i) {
        let sf = suffixes[i];
        if (self.str(self.pos, self.pos + sf.len()).eq(sf)) {
            self.pos += sf.len();
            break;
        }
    }
    let type = TokenType::INTEGER_LIT;
    if(dot) type = TokenType::FLOAT_LIT;
    return Token::new(type, self.str(start, self.pos));
}
  
  func kw(s: str): TokenType{
    if(s.eq("assert")) return TokenType::ASSERT_KW;
    if(s.eq("import")) return TokenType::IMPORT;
    return TokenType::EOF_;
  }
}


func lexer_test(){
  let lexer = Lexer::new("../tests/src/parser/lexer.x");
  for(let i = 0;i < 0; ++i){
    let t = lexer.next();
    let ts = t.print().str();
    print("tok = '%s'\n", ts);
  }
}