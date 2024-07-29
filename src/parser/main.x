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

static version_str = "1.0";
static vendor_str = "lang";
static compiler_name_str = "x";

func build_std(root: str, out_dir: str){
  use_cache = true;
  let config = CompilerConfig::new(format("{}/src", root));
  config
    .set_file(format("{}/src/std", root))
    .set_out(out_dir)
    .add_dir(format("{}/src", root))
    .set_link(LinkType::Static{"std.a".str()});

  let bin = Compiler::compile_dir(config);
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
    build_std(test_out());
    compile_dir2("../tests/std_test", format("{}/std.a", test_out()).str());
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
  let root = cmd.get_val("-root").unwrap();
  let build = format("{}/build", root);
  let run = false;
  let name = "x2";
  if(cmd.has()){
    name = cmd.peek.str();
  }
  let out_dir = format("{}/{}_out", build, name);
  build_std(out_dir.str());
  let args = format("{}/std.a libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++", out_dir);
  let config = CompilerConfig::new(get_std_path().str());
  let vendor = Path::name(cmd.get_root());
  print("vendor={}\n", vendor);
  config
    .set_file("../tests/parser".str())
    .set_out(out_dir)
    .add_dir(get_std_path())
    .set_link(LinkType::Binary{name, args.str(), run})
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
}

func own_test(id: i32){
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

  build_std(test_out());

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
  let std_path = get_std_path().str();
  let out_dir = get_out().str();
  let std = false;
  let run = !cmd.consume_any("-norun");
  let compile_only = cmd.consume_any("-nolink");
  let link_static = cmd.consume_any("-static");
  let link_shared = cmd.consume_any("-shared");
  let nostd = cmd.consume_any("-nostd");
  let noroot = cmd.consume_any("-noroot");
  let flags = "".str();
  if(cmd.has_any("-out")){
    out_dir.drop();
    out_dir = cmd.get_val("-out").unwrap();
  }
  if(cmd.has_any("-stdpath")){
    std_path.drop();
    std_path = cmd.get_val("-stdpath").unwrap();
  }
  if(cmd.has_any("-flags")){
    flags.drop();
    flags = cmd.get_val("-flags").unwrap();
  }
  if(cmd.consume_any("-std")){
    build_std(get_out());
    std = true;
  }
  let config = CompilerConfig::new(std_path.clone());
  while(cmd.has_any("-i")){
    let dir: String = cmd.get_val("-i").unwrap();
    config.add_dir(dir);
  }
  let path: String = cmd.get();
  let bin = bin_name(path.str());
  if(std){
    flags.append(" ");
    flags.append(get_stdlib());
  }
  config.set_file(path.str());
  config.set_out(out_dir);
  if(link_static){
    config.set_link(LinkType::Static{format("{}.a", get_filename(path.str()))});
  }else if(link_shared){
    config.set_link(LinkType::Dynamic{bin.str()});
  }else if(compile_only){
    config.set_link(LinkType::None);
  }else{
    config.set_link(LinkType::Binary{bin.str(), flags.str(), run});
  }
  config.nostd = nostd;
  if(!nostd){
    config.add_dir(std_path.clone());
  }
  if(is_dir(path.str())){
    if(!noroot){
      config.add_dir(path.str());
    }
    Compiler::compile_dir(config);
  }else{
    //config.add_dir(root());
    let out = Compiler::compile_single(config);
    out.drop();
  }
  path.drop();
  bin.drop();
  std_path.drop();
  flags.drop();
}

func handle(cmd: CmdArgs*){
  print("##########running##########\n");
  print_unit = false;
  if(!cmd.has()){
    print("enter a command\n");
    return;
  }
  if(cmd.is("-v")){
    print("{} version {} by {}\n", compiler_name_str, version_str, vendor_str);
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
    bootstrap();
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
    let ctx = Context::new(get_out().str(), get_std_path().str());
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