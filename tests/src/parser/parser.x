import parser/lexer
import parser/token
import parser/ast
import List
import String
import str
import map
import Option
import Box

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
    let lexer = Lexer::new("../tests/src/parser/parser.x");
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    print("%s\n", Fmt::str(unit).cstr());
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
      panic("unexpected token %s was expecting %s", t.print().cstr(), Fmt::str(tt).cstr());
    }
    
    func parse_unit(self): Unit*{
      while(self.has() && self.is(TokenType::IMPORT)){
        self.unit.imports.add(self.parse_import());
      }
      while(self.has()){
        let derives = List<Type>::new();
        if(self.is(TokenType::HASH)){
          self.pop();
          self.consume(TokenType::IDENT);
          self.consume(TokenType::LPAREN);
          derives.add(self.parse_type());
          while(self.is(TokenType::COMMA)){
            self.pop();
            derives.add(self.parse_type());
          }
          self.consume(TokenType::RPAREN);
        }
        if(self.is(TokenType::CLASS)){
          self.unit.items.add(Item::Struct{self.parse_struct(derives)});
        }else{
          panic("invalid top level decl: %s", self.peek().print().cstr());
        }
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
    
    func parse_struct(self, derives: List<Type>): StructDecl{
      let line = self.peek().line;
      self.consume(TokenType::CLASS);
      let type = self.parse_type();
      let is_generic = false;
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
          fields.add(self.parse_field());
        }
        self.consume(TokenType::RBRACE);
      }
      return StructDecl{.BaseDecl{line, &self.unit, type, false, is_generic, base, derives}, fields: fields};
    }
    
    func parse_field(self): FieldDecl{
      let line=self.peek().line;
      let name = self.pop().value;
      self.consume(TokenType::COLON);
      let type=self.parse_type();
      Fmt::str(type).dump();
      self.consume(TokenType::SEMI);
      return FieldDecl{name, type};
    }
    
    func parse_type(self): Type{
      if(self.is(TokenType::LBRACKET)){
        self.pop();
        let type = self.parse_type();
        if(self.is(TokenType::SEMI)){
          self.pop();
          let s = self.consume(TokenType::INTEGER_LIT);
          self.consume(TokenType::RBRACKET);
          return Type::Array{Box::new(type), i32::parse(&s.value)};
        }else{
          self.consume(TokenType::RBRACKET);
          return Type::Slice{Box::new(type)};
        }
      }
      let res = self.gen_part();
      //Fmt::str(res).dump();
      while(self.is(TokenType::COLON2)){
        self.pop();
        let part = self.gen_part();
        if let Type::Simple(scope, name, args) = (part){
          res = Type::Simple{Option::new(Box::new(res)), name, args};
        }
      }
      
      while (self.is(TokenType::STAR)) {
        Fmt::str(res).dump();
        self.consume(TokenType::STAR);
        res = Type::Pointer{Box::new(res)};
      }
      
      return res;
    }
    func gen_part(self): Type{
    //a<b>::c<d>
      let id = self.pop().value;
      if(self.is(TokenType::LT)){
        return Type::Simple{Option<Box<Type>>::None, id, self.generics()};
      }
      return Type::Simple{Option<Box<Type>>::None, id, List<Type>::new()};
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
}