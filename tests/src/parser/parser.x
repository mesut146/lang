import parser/lexer
import parser/token
import parser/ast
import List
import String
import str
import map

class Parser{
  lexer: Lexer*;
  tokens: List<Token>;
  pos: i32;
  is_marked: bool;
  mark: i32;
  unit: Unit;
}

impl Parser{
  func test(){
    let lexer = Lexer::new("../tests/src/parser/lexer.x");
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    print("%s\n", unit.debug().cstr());
  }


  func new(l: Lexer*): Parser{
    let res = Parser{l, List<Token>::new(), 0, false, 0, Unit::new(l.path)};
    res.fill();
    return res;
  }
  
  func fill(self) {
    while (true) {
        let t = self.lexer.next();
        if (t.is(TokenType::EOF_))
            return;
        if (t.is(TokenType::COMMENT))
            continue;
        self.tokens.add(t);
      }
    }
    
    func has(self): bool{
      return self.pos < self.tokens.len();
    }
    
    func is(self, tt: TokenType): bool{
      return self.has() && self.peek().type is tt;
    }
    
    func peek(self): Token*{
      return self.tokens.get_ptr(self.pos);
    }
    
    func pop(self): Token*{
      let t = self.tokens.get_ptr(self.pos);
      ++self.pos;
      return t;
    }
    
    func consume(self, tt: TokenType): Token*{
      let t = self.pop();
      if(t.type is tt) return t;
      panic("unexpected token");
    }
    
    func parse_unit(self): Unit*{
      while(self.has() && self.is(TokenType::IMPORT)){
        self.unit.imports.add(self.parse_import());
      }
      return &self.unit;
    }
    
    func parse_import(self): ImportStmt{
      self.consume(TokenType::IMPORT);
      let res = ImportStmt{list: List<String>::new()};
      res.list.add(self.pop().value);
      while(self.is(TokenType::DIV)){
        self.pop();
        res.list.add(self.pop().value);
      }
      return res;
    }
}