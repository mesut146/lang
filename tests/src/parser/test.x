import parser/lexer
import parser/token
import parser/parser
import parser/ast
import parser/printer
import parser/resolver
import parser/compiler
import parser/bridge
import std/map
import std/io

func lexer_test(){
  let lexer = Lexer::new("../tests/src/parser/parser.x".str());
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
    let lexer = Lexer::new("../tests/src/parser/parser.x".str());
    let parser = Parser::new(&lexer);
    let unit = parser.parse_unit();
    print("%s\n", Fmt::str(unit).cstr());
}

func resolver_test(){
  print("resolver_test\n");
  let root = "../tests/src";
  let ctx = Context::new(root.str());
  resolver_dir(&ctx, root);
  resolver_dir(&ctx, "../tests/src/std");
}

func resolver_dir(ctx: Context*, dir: str){
  let list = list(dir);
  for(let i = 0;i < list.len();++i){
    let name = list.get_ptr(i);
    if(!name.str().ends_with(".x")) continue;
    let file = String::new(dir);
    file.append("/");
    file.append(name.str());
    if(is_dir(file.str())) continue;
    let r = Resolver::new(file, ctx);
    r.resolve_all();
  }
}

func compile_dir(cmp: Compiler*, dir: str){
  let list = list(dir);
  for(let i = 0;i < list.len();++i){
    let name = list.get_ptr(i);
    if(!name.str().ends_with(".x")) continue;
    let file = String::new(dir);
    file.append("/");
    file.append(name.str());
    if(is_dir(file.str())) continue;
    cmp.compile(file.str());
    cmp.link_run(name.substr(0, name.len() as i32 - 2),"");
  }
}

func compile(cmp: Compiler*, file: str){
    cmp.compile(file);
    let name = file.substr(file.indexOf("/", 0)+1);
    cmp.link_run(name.substr(0, name.len() as i32 - 2),"");
}

func compiler_test(){
  print("compiler_test\n");
  let root = "../tests/src";
  let ctx = Context::new(root.str());
  let cmp = Compiler::new(ctx);
  compile(&cmp, "../tests/src/infix.x");
  compile_dir(&cmp, root);
  compile_dir(&cmp, "../tests/src/std");
}

func main(){
  print("##########running##########\n");
  //lexer_test();
  //parser_test();
  //resolver_test();
  compiler_test();
}