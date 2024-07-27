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
func get_stdlib(): str{
  return "./bt_out/std.a";
}
func get_std_path(): str{
  return "../tests";
}

static version_str = "1.0";
static vendor_str = "lang";
static compiler_name_str = "x";

func build_std(out_dir: str){
  use_cache = true;
  let config = CompilerConfig::new(get_std_path().str());
  config
    .set_file("../tests/std".str())
    .set_out(out_dir)
    .add_dir(get_std_path())
    .set_link(LinkType::Static{"std.a"});

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
    build_std(get_out());
    compile_dir2("../tests/std_test", format("{}/std.a", get_out()).str());
  }else{
    let config = CompilerConfig::new(get_std_path().str());
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

func bootstrap(run: bool, name: str, vendor: str){
  print("test::bootstrap\n");
  bootstrap = true;
  let out_dir = format("{}_out", name);
  build_std(out_dir.str());
  let args = format("{}/std.a libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++", out_dir);
  let config = CompilerConfig::new(get_std_path().str());
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
  bin.drop();

  let binc = bin2.cstr();
  set_as_executable(binc.ptr());
  binc.drop();
  args.drop();
}

func own_test(id: i32){
  print("test::own_test\n");
  drop_enabled = true;
  let config = CompilerConfig::new(get_std_path().str());
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
  drop_enabled = false;
}

func main(argc: i32, args: i8**){
  let cmd = CmdArgs::new(argc, args);
  handle(&cmd);
  cmd.drop();
}

func handle_c(cmd: CmdArgs*){
  cmd.consume();
  use_cache = false;
  let out_dir = get_out().str();
  let std = false;
  if(cmd.is("-std")){
    cmd.consume();
    build_std(get_out());
    std = true;
  }
  if(cmd.is("-out")){
    cmd.consume();
    out_dir.drop();
    out_dir = cmd.get();
  }
  let run = true;
  if(cmd.is("-norun")){
    cmd.consume();
    run = false;
  }
  let path: String = cmd.get();
  if(is_dir(path.str())){
    let bin = bin_name(path.str());
    let config = CompilerConfig::new(get_std_path().str());
    config
      .set_file(path.str())
      .set_out(out_dir)
      .add_dir(get_std_path())
      .set_link(LinkType::Binary{bin.str(), "", run});
    Compiler::compile_dir(config);
    bin.drop();
  }else{
    let config = CompilerConfig::new(get_std_path().str());
    config
    .set_file(path)
    .set_out(out_dir)
    .add_dir(root());

    if(std){
      config.set_link(LinkType::Binary{"a.out", get_stdlib(), false});
    }else{
      config.set_link(LinkType::Binary{"a.out", "", false});
    }
    let out = Compiler::compile_single(config);
    out.drop();
  }
}

func handle(cmd: CmdArgs*){
  print("##########running##########\n");
  print_unit = false;
  if(!cmd.has()){
    bootstrap(false, "x2", Path::name(cmd.get_root()));
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
    cmd.consume();
    let name = "x2";
    if(cmd.has()){
      name = cmd.peek().str();
    }
    bootstrap(false, name, Path::name(cmd.get_root()));
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
    print("resolve done {} bcnt: {}\n", path, blocks);
    ctx.drop();
    path.drop();
    return;
  }else{
    panic("invalid cmd: {}", cmd.args);
  }
}