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
import parser/cache
import std/map
import std/io
import std/libc
import std/stack

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

func build_std(out_dir: str){
  use_cache = true;
  Compiler::compile_dir("../tests/std", out_dir, root(), LinkType::Static{"std.a"});
}

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
    build_std(get_out());
    compile_dir2("../tests/std_test", format("{}/std.a", get_out()).str());
  }else{
    compile_dir2("../tests/normal", "");
  }
}

func bootstrap(run: bool, out_dir: str){
  print("test::bootstrap\n");
  build_std(out_dir);
  let args = format("{}/std.a libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++", out_dir);
  let name = "x_".str();
  if(out_dir.contains("/")){
    let rest = out_dir.substr(out_dir.lastIndexOf("/") + 1);
    name.append(rest);
  }else{
    name.append(out_dir);
  }
  let bin = Compiler::compile_dir("../tests/parser", out_dir, root(), LinkType::Binary{name.str(), args.str(), run});
  let bin2 = format("./{}", name);
  File::copy(bin.str(), bin2.str());
  print("wrote {}\n", bin2);
  set_as_executable(bin2.cstr().ptr());
}

func main(argc: i32, args: i8**){
  print("##########running##########\n");
  print_unit = false;
  if(argc == 1){
    bootstrap(true, get_out());
    return;
  }
  let cmd = Args::new(argc, args);
  let arg = cmd.get();
  if(arg.eq("test")){
    compiler_test(false);
    return;
  }
  else if(arg.eq("test2")){
    compiler_test(true);
    return;
  }else if(arg.eq("std")){
    build_std(get_out());
  }else if(arg.eq("bt")){
    let out = get_out();
    if(cmd.has()){
      out = cmd.get().str();
    }
    bootstrap(false, out);
  }else if(arg.eq("leak")){
    Compiler::compile_single(root(), get_out(), "../tests/normal/alloc.x", "");
  }
  else if(arg.eq("c")){
    let path = get_arg(args, 2);
    if(is_dir(path)){
      Compiler::compile_dir(path, get_out(), root(), LinkType::Binary{bin_name(path).str(), "", true});
    }else{
      Compiler::compile_single(root(), get_out(), path, "");
    }
  }else{
    panic("invalid cmd: {}", arg);
  }
}