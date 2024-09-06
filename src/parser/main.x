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
import parser/own_model
import parser/cache
import parser/tests
import std/map
import std/io
import std/libc
import std/stack

func get_vendor(): str{
  return std::env("vendor").unwrap_or("x");
}
func get_compiler_name(): str{
  return std::env("compiler_name").unwrap_or("x");
}
func get_version(): str{
  return std::env("version").unwrap_or("1.6");
}

func build_std(std_dir: str, out_dir: str): String{
  return build_std(std_dir, out_dir, true);
}

func build_std(std_dir: str, out_dir: str, use_cache0: bool): String{
  use_cache = use_cache0;
  let src_dir = Path::parent(std_dir);
  let config = CompilerConfig::new(src_dir.str());
  config
    .set_file(std_dir)
    .set_out(out_dir)
    .add_dir(src_dir)
    .set_link(LinkType::Static{"std.a".str()});
  config.root_dir.set(std_dir.str());
  let lib = Compiler::compile_dir(config);
  return lib;
}

func bootstrap(cmd: CmdArgs*){
  print("main::bootstrap()\n");
  bootstrap = true;
  cmd.consume();
  let root_opt = cmd.get_val("-root");
  if(root_opt.is_none()){
    root_opt.set(find_root(cmd.get_root()).clone());
  }
  let is_static = cmd.consume_any("-static");
  let root = root_opt.unwrap();
  let build = format("{}/build", root);
  let src_dir = format("{}/src", root);
  let std_dir = format("{}/src/std", root);
  let name = "x2";
  if(cmd.has()){
    name = cmd.peek().str();
  }
  let vendor: str = Path::name(cmd.get_root());
  setenv2("vendor", vendor, 1);
  //setenv2("vendor", get_compiler_name(), 1);
  setenv2("compiler_name", name, 1);
  let out_dir = format("{}/{}_out", &build, name);
  let config = CompilerConfig::new(src_dir.clone());
  if(is_static){
    config.set_link(LinkType::Static{name.str()});
  }else{
    let stdlib = build_std(std_dir.str(), out_dir.str());
    let args = format("{} {}/cpp_bridge/build/libbridge.a -lstdc++ -lm /usr/lib/llvm-16/lib/libLLVM.so", &stdlib, &root);
    config.set_link(LinkType::Binary{name, args.str(), false});
    stdlib.drop();
    args.drop();
  }
  config
    .set_file(format("{}/parser", &src_dir))
    .set_out(out_dir)
    .add_dir(src_dir.clone());
  config.root_dir.set(root.clone());
  let bin = Compiler::compile_dir(config);
  let bin2 = format("{}/{}", &build, name);
  File::copy(bin.str(), bin2.str());
  print("wrote {}\n", bin2);
  
  let binc = bin2.cstr();
  set_as_executable(binc.ptr());
  binc.drop();
  root.drop();
  bin.drop();
  build.drop();
  src_dir.drop();
  std_dir.drop();
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
  let flags = cmd.get_val_or("-flags", "".str());
  let name = cmd.get_val("-name");
  let config = CompilerConfig::new();
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

func print_version(){
  print("{} version {} by {}\n", get_compiler_name(), get_version(), get_vendor());
}

func handle(cmd: CmdArgs*){
  print("##########running##########\n");
  print_unit = false;
  //print_version();
  if(!cmd.has()){
    print("enter a command\n");
    return;
  }
  if(cmd.is("-v")){
    print_version();
    return;
  }
  if(handle_tests(cmd)){
    return;
  }
  if(cmd.is("std")){
    handle_std(cmd);
    return;
  }else if(cmd.is("bt")){
    bootstrap(cmd);
    return;
  }
  else if(cmd.is("c")){
    handle_c(cmd);
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