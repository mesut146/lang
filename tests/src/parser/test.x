import parser/lexer
import parser/token
import parser/parser
import parser/ast
import std/map

func lexer_test(){
  let lexer = Lexer::new("../tests/src/parser/lexer.x");
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
    let lexer = Lexer::new("../tests/src/parser/lexer.x");
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    print("%s\n", Fmt::str(unit).cstr());
  }


func main(){
  //lexer_test();
  parser_test();
}