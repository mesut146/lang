import parser/lexer
import parser/token
import parser/parser
import parser/ast
import parser/printer
import parser/resolver
import std/map
import std/io

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
  let dir = "../tests/src";
  let list = list(dir);
  for(let i = 0;i < list.len();++i){
    let name = list.get_ptr(i);
    if(!name.str().ends_with(".x")) continue;
    let file = String::new(dir);
    file.append("/");
    file.append(name.str());
    if(is_dir(file.str())) continue;
    let r = Resolver::new(file.str());
    r.resolve_all();
  }
  //let s = "../tests/src/lit.x";
}

func main(){
  print("##########running##########\n");
  //lexer_test();
  //parser_test();
  resolver_test();
}