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
  let bin = Compiler::compile_dir("../tests/std", out_dir, root(), LinkType::Static{"std.a"});
  bin.drop();
}

func compile_dir2(dir: str, args: str){
  compile_dir2(dir, args, Option<str>::new());
}

func compile_dir2(dir: str, args: str, exc: Option<str>){
  let list: List<String> = list(dir);
  list.sort();
  print("compile_dir '{}' -> {} elems\n", dir, list.len());
  for(let i = 0;i < list.len();++i){
    let name: String* = list.get_ptr(i);
    if(!name.str().ends_with(".x")) continue;
    if(exc.is_some() && name.eq(*exc.get())){
      continue;
    }
    let file: String = dir.str();
    file.append("/");
    file.append(name);
    if(is_dir(file.str())) continue;
    let config = CompilerConfig::new();
    config
      .set_file(file)
      .set_out(get_out())
      .add_dir(root())
      .set_link(LinkType::Binary{"a.out", args, true});
    let bin = Compiler::compile_single(config);
    bin.drop();
  }
  list.drop();
}

func compiler_test(std_test: bool){
  print("compiler_test\n");
  if(std_test){
    build_std(get_out());
    compile_dir2("../tests/std_test", format("{}/std.a", get_out()).str());
  }else{
    let config = CompilerConfig::new();
    config
      .set_file("../tests/std/rt.x")
      .set_out(get_out())
      .add_dir(root())
      .set_link(LinkType::Static{"rt.a"});
    let lib = Compiler::compile_single(config);
    compile_dir2("../tests/normal", lib.str());
    lib.drop();
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
  bin.drop();

  let binc = bin2.cstr();
  set_as_executable(binc.ptr());
  binc.drop();
  name.drop();
  args.drop();
}

func own_test(id: i32){
  print("test::own_test\n");
  let config = CompilerConfig::new();
  config
    .set_file("../tests/own/common.x")
    .set_out(get_out())
    .add_dir(root())
    .set_link(LinkType::Static{"common.a"});
  let bin = Compiler::compile_single(config);
  bin.drop();

  build_std(get_out());

  let args = format("{}/common.a {}/std.a", get_out(), get_out());
  if(id == 1){
    compile_dir2("../tests/own", args.str(), Option::new("common.x"));
  }else{
    compile_dir2("../tests/own_if", args.str(), Option::new("common.x"));
  }
  args.drop();
}

func main(argc: i32, args: i8**){
  let cmd = CmdArgs::new(argc, args);
  handle(&cmd);
  cmd.drop();
}

func handle(cmd: CmdArgs*){
  print("##########running##########\n");
  print_unit = false;
  if(!cmd.has()){
    bootstrap(false, get_out());
    return;
  }
  if(cmd.is("own")){
    own_test(1);
    return;
  }
  if(cmd.is("own2")){
    own_test(2);
    return;
  }
  if(cmd.is("test")){
    compiler_test(false);
    return;
  }
  else if(cmd.is("test2")){
    compiler_test(true);
    return;
  }else if(cmd.is("std")){
    build_std(get_out());
  }else if(cmd.is("bt")){
    cmd.consume();
    let out = get_out();
    if(cmd.has()){
      print("cmd len={}\n", cmd.args.len());
      out = cmd.peek().str();
    }
    bootstrap(false, out);
  }
  else if(cmd.is("c")){
    let path: String = cmd.get();
    if(is_dir(path.str())){
      let bin = bin_name(path.str());
      Compiler::compile_dir(path.str(), get_out(), root(), LinkType::Binary{bin.str(), "", true});
      bin.drop();
    }else{
      let config = CompilerConfig::new();
      config
      .set_file(path)
      .set_out(get_out())
      .add_dir(root())
      .set_link(LinkType::Binary{"a.out", "", false});
      let out = Compiler::compile_single(config);
      out.drop();
    }
  }else{
    panic("invalid cmd: {}", cmd.args);
  }
}