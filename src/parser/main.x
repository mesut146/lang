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
func test_out(): str{
  return "./test_out";
}
func get_stdlib(): str{
  return "./bt_out/std.a";
}
func get_std_path(): str{
  return "../tests";
}

func get_vendor(): str{
  return std::env("vendor").unwrap_or("lang");
}
func get_compiler_name(): str{
  return std::env("compiler_name").unwrap_or("x");
}
func get_version(): str{
  return std::env("version").unwrap_or("1.1");
}

func build_std(std_dir: str, out_dir: str): String{
  use_cache = true;
  let src_dir = Path::parent(std_dir);
  let config = CompilerConfig::new(src_dir.str());
  config
    .set_file(std_dir)
    .set_out(out_dir)
    .add_dir(src_dir)
    .set_link(LinkType::Static{"std.a".str()});

  let lib = Compiler::compile_dir(config);
  return lib;
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
    let config = CompilerConfig::new(get_std_path().str());
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
    //build_std(test_out());
    compile_dir2("../tests/std_test", format("{}/std.a", test_out()).str());
    panic("");
  }else{
    let config = CompilerConfig::new(get_std_path().str());
    config
      .set_file("../tests/std/rt.x")
      .set_out(test_out())
      .add_dir(root())
      .set_link(LinkType::Static{"rt.a".str()});
    let lib = Compiler::compile_single(config);
    compile_dir2("../tests/normal", lib.str());
    lib.drop();
  }
}

func bootstrap(cmd: CmdArgs*){
  print("test::bootstrap\n");
  bootstrap = true;
  cmd.consume();
  let root = cmd.get_val2("-root");
  let build = format("{}/build", root);
  let src_dir = format("{}/src", root);
  let std_dir = format("{}/src/std", root);
  let name = "x2";
  if(cmd.has()){
    name = cmd.peek().str();
  }
  let out_dir = format("{}/{}_out", &build, name);
  let stdlib = build_std(std_dir.str(), out_dir.str());
  let args = format("{} {}/cpp_bridge/build/libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++", &stdlib, &root);
  let config = CompilerConfig::new(src_dir.clone());
  let vendor = Path::name(cmd.get_root());
  print("vendor={}\n", vendor);
  config
    .set_file(format("{}/parser", &src_dir))
    .set_out(out_dir)
    .add_dir(src_dir.clone())
    .set_link(LinkType::Binary{name, args.str(), false})
    .set_vendor(vendor);
  let bin = Compiler::compile_dir(config);
  let bin2 = format("./{}", name);
  File::copy(bin.str(), bin2.str());
  print("wrote {}\n", bin2);
  
  let binc = bin2.cstr();
  set_as_executable(binc.ptr());
  binc.drop();
  args.drop();
  root.drop();
  bin.drop();
  build.drop();
  stdlib.drop();
  src_dir.drop();
  std_dir.drop();
}

func own_test(id: i32, std_dir: str){
  print("test::own_test\n");
  drop_enabled = true;
  let config = CompilerConfig::new(get_std_path().str());
  config
    .set_file("../tests/own/common.x")
    .set_out(test_out())
    .add_dir(root())
    .set_link(LinkType::Static{"common.a".str()});
  let bin = Compiler::compile_single(config);
  bin.drop();

  let lib = build_std(std_dir, test_out());
  lib.drop();

  let args = format("{}/common.a {}/std.a", test_out(), test_out());
  if(id == 1){
    compile_dir2("../tests/own", args.str(), Option::new("common.x"));
  }else{
    compile_dir2("../tests/own_if", args.str(), Option::new("common.x"));
  }
  args.drop();
  drop_enabled = false;
}

func handle_c(cmd: CmdArgs*){
  cmd.consume();
  use_cache = cmd.consume_any("-cache");
  let out_dir = cmd.get_val2("-out");
  let run = !cmd.consume_any("-norun");
  let compile_only = cmd.consume_any("-nolink");
  let link_static = cmd.consume_any("-static");
  let link_shared = cmd.consume_any("-shared");
  let nostd = cmd.consume_any("-nostd");
  let noroot = cmd.consume_any("-noroot");
  let flags = cmd.get_val_or("-flags", "".str());
  let name = cmd.get_val("-name");
  let config = CompilerConfig::new();
  config.set_vendor(get_vendor());
  while(cmd.has_any("-i")){
    let dir: String = cmd.get_val("-i").unwrap();
    config.add_dir(dir);
  }
  if(cmd.has_any("-stdpath")){
    let std_path = cmd.get_val2("-stdpath");
    config.add_dir(std_path.clone());
    config.set_std(std_path.clone());
    if(cmd.consume_any("-std")){
      let lib = build_std(std_path.str(), out_dir.str());
      flags.append(" ");
      flags.append(lib.str());
      lib.drop();
    }
    std_path.drop();
  }
  let path: String = cmd.get();
  let bin = bin_name(path.str());
  config.set_file(path.str());
  config.set_out(out_dir.clone());
  if(link_static){
    config.set_link(LinkType::Static{format("{}.a", get_filename(path.str()))});
  }else if(link_shared){
    config.set_link(LinkType::Dynamic{format("{}.a", get_filename(path.str()))});
  }else if(compile_only){
    config.set_link(LinkType::None);
  }else{
    if(name.is_some()){
      config.set_link(LinkType::Binary{name.get().str(), flags.str(), run});
    }else{
      config.set_link(LinkType::Binary{bin.str(), flags.str(), run});
    }
  }
  if(is_dir(path.str())){
    if(!noroot){
      config.add_dir(path.str());
    }
    let out = Compiler::compile_dir(config);
    out.drop();
  }else{
    let out = Compiler::compile_single(config);
    out.drop();
  }
  path.drop();
  bin.drop();
  flags.drop();
  out_dir.drop();
  name.drop();
}

func handle_std(cmd: CmdArgs*){
  cmd.consume();
  let root = cmd.get_val2("-root");
  let out = format("{}/build/std_out", root);
  if(cmd.has_any("-out")){
    out.drop();
    out = cmd.get_val2("-out");
  }
  let std_dir = format("{}/src/std", root);
  let lib = build_std(std_dir.str(), out.str());
  root.drop();
  out.drop();
  std_dir.drop();
  lib.drop();
}

func handle(cmd: CmdArgs*){
  print("##########running##########\n");
  print_unit = false;
  print("vendor={} name={} version={}\n", get_vendor(), get_compiler_name(), get_version());
  if(!cmd.has()){
    print("enter a command\n");
    return;
  }
  if(cmd.is("-v")){
    print("{} version {} by {}\n", get_compiler_name(), get_version(), get_vendor());
    return;
  }
  if(cmd.is("own")){
    //own_test(1);
    return;
  }
  if(cmd.is("own2")){
    //own_test(2);
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
    handle_std(cmd);
    return;
  }else if(cmd.is("bt")){
    bootstrap(cmd);
    return;
  }
  else if(cmd.is("c")){
    handle_c(cmd);
    return;
  }else if(cmd.is("p")){
    //parse test
    cmd.consume();
    let path = cmd.get();
    let parser = Parser::from_path(path);
    print("parse done {}\n", parser.path);
    parser.drop();
    return;
  }else if(cmd.is("r")){
    //resolver test
    cmd.consume();
    let path = cmd.get();
    let ctx = Context::new(get_out().str(), Option::new(get_std_path().str()));
    let resolver = ctx.create_resolver(&path);
    print("resolve done {}\n", path);
    ctx.drop();
    path.drop();
    return;
  }else{
    panic("invalid cmd: {}", cmd.args);
  }
}

func main(argc: i32, args: i8**){
  let cmd = CmdArgs::new(argc, args);
  handle(&cmd);
  cmd.drop();
}