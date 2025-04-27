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
import std/fs
import std/libc
import std/stack
import std/result

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

func build_std(std_dir: str, out_dir: str, use_cache: bool): String{
  let src_dir = Path::parent(std_dir);
  let config = CompilerConfig::new(src_dir.str());
  config.use_cache = use_cache;
  config
    .set_file(std_dir)
    .set_out(out_dir)
    .add_dir(src_dir)
    .set_link(LinkType::Static{"std.a".str()});
  config.root_dir.set(std_dir.str());
  let lib = Compiler::compile_dir(config);
  return lib;
}

func trim_nl(s: String): String{
  if(s.str().ends_with("\n")){
    return s.substr(0, s.len() - 1).owned();
  }
  return s;
}

func bootstrap(cmd: CmdArgs*){
  print("main::bootstrap()\n");
  bootstrap = true;
  cmd.consume();
  let root_opt = cmd.get_val("-root");
  if(root_opt.is_none()){
    root_opt.set(find_root(cmd.get_root()).clone());
  }
  let jobs = cmd.get_val("-j");
  let verbose_all = cmd.consume_any("-v");
  let is_static = cmd.consume_any("-static");
  let is_static_llvm = cmd.consume_any("-static-llvm");
  let sng = cmd.get_val("-sng");
  let root = root_opt.unwrap();
  let build = format("{}/build", root);
  let src_dir = format("{}/src", root);
  let std_dir = format("{}/src/std", root);
  let llvm_only = cmd.consume_any("-llvm-only");

  if(cmd.has_any("-target")){
    let target = cmd.get_val("-target").unwrap();
    if(target.eq("x86_64-unknown-linux-gnu") || target.eq("x86_64")){
      std::setenv("target_triple", "x86_64-unknown-linux-gnu");
    }
    else if(target.eq("aarch64-linux-gnu") || target.eq("arm64")){
      std::setenv("target_triple", "aarch64-linux-gnu");
    }
    else if(target.eq("android")){
      std::setenv("target_triple", "aarch64-linux-android");
    }
    else{
      panic("unsupported target: {}", target);
    }
  }


  let name = "x2";
  if(cmd.has()){
    name = cmd.get().str();
  }
  cmd.end();
  let vendor: str = Path::name(cmd.get_root());
  std::setenv("vendor", vendor);
  //std::setenv("vendor", get_compiler_name());
  std::setenv("compiler_name", name);
  let out_dir = format("{}/{}_out", &build, name);
  let config = CompilerConfig::new(src_dir.clone());
  config.verbose_all = verbose_all;
  config.llvm_only = llvm_only;

  let stdlib = build_std(std_dir.str(), out_dir.str());
  let llvm_config = {
    let opt = std::getenv("llvm_config");
    if(opt.is_some()){
      opt.unwrap()
    }else{
      let p = Process::run("llvm-config-19 2>&1");
      let res = p.read_close();
      if(res.is_ok()){
        "llvm-config-19"
      }else{
        "llvm-config"
      }
    }
  };
  let libdir: String = {
    let libdir_opt = std::getenv("libdir");
    if(libdir_opt.is_none()){
      let p = Process::run(format("{} --libdir 2>&1", llvm_config).str());
      let res = p.read_close();
      if(res.is_ok()){
        trim_nl(res.unwrap())
      }else{
        //panic!("failed to get libdir: {}", res);
        "/usr/lib/llvm-19/lib".owned()
      }
    }else{
      libdir_opt.unwrap().owned()
    }
  };

  let libbridge = {
    let libbridge_opt = std::getenv("libbridge");
    if(libbridge_opt.is_some()){
      libbridge_opt.unwrap().owned()
    }
    else{
      let lib = format("{}/cpp_bridge/build/libbridge.a", &root);
      if(!File::exists(lib.str())){
        print("building libbridge\n");
        let out = Process::run(format("{root}/cpp_bridge/x.sh").str()).read_close();
        if(out.is_ok() && !out.get().empty()){
          print("{}\n", out.unwrap());
        }
        if(!File::exists(lib.str())){
          panic("failed to build libbridge");
        }
      }
      lib
    }
  };

  if(is_static_llvm){
    config.set_link(LinkType::Static{format("{}.a", name)});
  }
  else if(is_static){
    config.set_link(LinkType::Static{format("{}.a", name)});
  }else{
    let args = format("{} {libbridge} -lstdc++ -lm {}/libLLVM.so", &stdlib, libdir);
    config.set_link(LinkType::Binary{name.owned(), args, false});
  }
  
  config
    .set_file(format("{}/parser", &src_dir))
    .set_out(out_dir.clone())
    .add_dir(src_dir.clone());
  config.incremental_enabled = false;
  if(jobs.is_some()){
    config.set_jobs(i32::parse(jobs.get().str()).unwrap());
  }
  config.root_dir.set(root.clone());
  if(sng.is_some()){
    config.set_link(LinkType::None);
    config.set_file(format("{}/parser/{}", &src_dir, sng.get()));
    Compiler::compile_single(config);
    sng.drop();
    return;
  }
  let bin = Compiler::compile_dir(config);
  if(is_static_llvm){
    let linker = get_linker();
    let llvm = Process::run(format("{llvm_config} --link-static --libs core target aarch64 X86").str()).read_close().unwrap();
    llvm = trim_nl(llvm);
    //print("llvm={}\n", llvm);
    //let sys = "-lstdc++ -lrt -ldl -lz -lzstd -ltinfo -lxml2";
    let bin_path = format("{}/{}-static", out_dir, name);
    let sys = "-Wl,-Bstatic -lz -lzstd ltinfo";
    let cmd_link = format("{linker} -o {bin_path} -lstdc++ -lm {bin} {stdlib} {libbridge} -L{libdir} {llvm} {sys}");
    //cmd_link.append(" /lib/x86_64-linux-gnu/libtinfo.a");
    //cmd_link.append(" /lib/x86_64-linux-gnu/libzstd.a");
    //cmd_link.append(" /lib/x86_64-linux-gnu/libz.a");
    //print("cmd={}\n", cmd_link);
    let proc = Process::run(cmd_link.str());
    let proc_out = proc.read_close();
    if(proc_out.is_ok() && !proc_out.get().empty()){
      panic("proc={}\ncmd={}\n", proc_out.unwrap(), cmd_link);
    }
    if(proc_out.is_ok()){
      let bin2 = format("{}/{}", build, name);
      File::copy(bin_path.str(), bin2.str());
      //set_as_executable(bin2.cstr().ptr());
      File::set_permissions(bin2.str(), Permissions::from_mode(/*777*/511));
      bin2.drop();
    }
    cmd_link.drop();
    llvm.drop();
  }
  else if(!is_static){
    let bin2 = format("{}/{}", &build, name);
    File::copy(bin.str(), bin2.str());
    print("wrote {}\n", bin2);
    //let binc = bin2.cstr();
    // set_as_executable(binc.ptr());
    File::set_permissions(bin2.str(), Permissions::from_mode(511));
    //bin2.drop();
  }
  root.drop();
  bin.drop();
  build.drop();
  src_dir.drop();
  std_dir.drop();
  stdlib.drop();
}

func bin_name(path: str): String{
  let name = Path::name(path);
  return format("{}.bin", Path::noext(name));
}

func handle_c(cmd: CmdArgs*){
  cmd.consume();
  let out_dir = cmd.get_val2("-out");
  let run = !cmd.consume_any("-norun");
  let compile_only = cmd.consume_any("-nolink");
  let link_static = cmd.consume_any("-static");
  let link_shared = cmd.consume_any("-shared");
  let flags = cmd.get_val_or("-flags", "".str());
  let name: Option<String> = cmd.get_val("-name");
  let incremental = cmd.consume_any("-inc");
  let config = CompilerConfig::new();
  config.use_cache = cmd.consume_any("-cache");
  config.incremental_enabled = incremental;
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
  
  config.set_file(path.str());
  config.set_out(out_dir.clone());
  if(link_static){
    config.set_link(LinkType::Static{format("{}.a", Path::name(path.str()))});
  }else if(link_shared){
    config.set_link(LinkType::Dynamic{format("{}.so", Path::name(path.str()))});
  }else if(compile_only){
    config.set_link(LinkType::None);
  }else{
    if(name.is_some()){
      config.set_link(LinkType::Binary{name.unwrap(), flags, run});
    }else{
      let bin: String = bin_name(path.str());
      config.set_link(LinkType::Binary{bin, flags, run});
      name.drop();
    }
  }
  if(File::is_dir(path.str())){
    let out = Compiler::compile_dir(config);
    out.drop();
  }else{
    let out = Compiler::compile_single(config);
    out.drop();
  }
  path.drop();
  out_dir.drop();
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
  //print_version();
  if(!cmd.has()){
    print("enter a command\n");
    return;
  }
  if(cmd.is("-v")){
    print_version();
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
  }else if(cmd.is("f")){
    let dir = format("{}/parser", get_src_dir());
    let out = format("{}/parser2", get_src_dir());
    format_dir(dir.str(), out.str());
    return;
  }
  else if(handle_tests(cmd)){
    return;
  }else{
    panic("invalid cmd: {:?}", cmd.args);
  }
}

func main(argc: i32, args: i8**){
  let cmd = CmdArgs::new(argc, args);
  handle(&cmd);
  cmd.drop();
}