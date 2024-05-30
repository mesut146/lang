import parser/lexer
import parser/token
import parser/parser
import parser/ast
import parser/printer
import parser/resolver
import parser/compiler
import parser/debug_helper
import parser/bridge
import parser/utils
import parser/ownership
import std/map
import std/io
import std/libc

func root(): str{
  return "../tests";
}
func get_out(): str{
  return "./bt_out";
}

func make_context(): Context{
  let out_dir = get_out();
  create_dir(out_dir);
  return Context::new(root().str(), out_dir.str());
}

func build_std(){
  Compiler::compile_dir("../tests/std", get_out(), root(), "", LinkType::Static{"std.a"});
}

/*func compile_dir(cmp: Compiler*, dir: str, link: bool, args: str){
  let list = list(dir);
  print("compile_dir '{}' -> {} elems\n", dir, list.len());
  for(let i = 0;i < list.len();++i){
    let name_c: String* = list.get_ptr(i);
    let name: str = name_c.get(); 
    if(!name.ends_with(".x")) continue;
    let file: String = dir.str();
    file.append("/");
    file.append(name);
    if(is_dir(file.str())) continue;
    cmp.compile(file.cstr());
    if(link){
      cmp.link_run(bin_name(name).str(), args);
    }
  }
}*/
func compile_dir2(dir: str, args: str){
  let list: List<String> = list(dir);
  list.sort();
  print("compile_dir '{}' -> {} elems\n", dir, list.len());
  for(let i = 0;i < list.len();++i){
    let name: String* = list.get_ptr(i);
    if(!name.str().ends_with(".x")) continue;
    let file: String = dir.str();
    file.append("/");
    file.append(name);
    if(is_dir(file.str())) continue;
    Compiler::compile_single(root(), get_out(), file.str(), args);
  }
}

func compiler_test(std_test: bool){
  print("compiler_test\n");
  if(std_test){
    build_std();
    compile_dir2("../tests/std_test", format("{}/std.a", get_out()).str());
  }else{
    compile_dir2("../tests/normal", "");
  }
}

func bootstrap(){
  print("test::bootstrap\n");
  build_std();
  //Compiler::compile_dir("../tests/parser", get_out(), root(), "", LinkType::Binary{"x2"});
  //cmp.link_run("x", "libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++");
}

func main(argc: i32, args: i8**){
  print("##########running##########\n");
  print_unit = false;
  if(argc == 1){
    bootstrap();
    return;
  }
  let a1 = get_arg(args, 1);
  if(a1.eq("test")){
    compiler_test(false);
    return;
  }
  else if(a1.eq("test2")){
    compiler_test(true);
    return;
  }else if(a1.eq("std")){
    build_std();
  }
  else if(a1.eq("c")){
    let path = get_arg(args, 2);
    if(is_dir(path)){
      Compiler::compile_dir(path, get_out(), root(), "", LinkType::Binary{bin_name(path).str()});
    }else{
      Compiler::compile_single(root(), get_out(), path, "");
    }
  }

  
}