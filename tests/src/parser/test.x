import parser/lexer
import parser/token
import parser/parser
import parser/ast
import parser/resolver
import std/map

func lexer_test(){
  let lexer = Lexer::new("../tests/src/parser/parser.x");
  let i=0;
  for(;; ++i){
    let t = lexer.next();
    print("%s\n", t.print().cstr());
    if(t.is(TokenType::EOF_)) break;
  }
  print("%d tokens\n", i);
  print("lexer_test done\n");
}

func parser_test(){
    let lexer = Lexer::new("../tests/src/parser/parser.x");
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    print("%s\n", Fmt::str(unit).cstr());
}

func resolver_test(){
  //let s = "../tests/src/parser/token.x";
  let s = "../tests/src/lit.x";
  let r = Resolver::new(s);
  r.resolve_all();
}

func main(){
  //lexer_test();
  //parser_test();
  resolver_test();
}