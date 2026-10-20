import std/map
import std/io
import std/fs
import std/libc
import std/stack
import std/result

import ast/lexer
import ast/token
import ast/parser
import ast/ast
import ast/printer
import ast/utils

import resolver/resolver

import backend/compiler
import backend/debug_helper
import parser/ownership
import parser/own_model
import parser/cache

func get_vendor(): str{
  return std::env!("vendor").unwrap_or("x");
}
func get_compiler_name(): str{
  return std::env!("compiler_name").unwrap_or("x");
}
func get_version(): str{
  return std::env!("version").unwrap_or("1.00");
}

//Default worker count for a directory compile: online CPUs from
///proc/cpuinfo, capped at 8 -- each worker is a full compilation (parser +
//resolver + emitter + LLVM module), so a 64-core host should not start 64 of
//them. Falls back to 4 when /proc is unavailable, and never returns 0.
func cpu_count(): i32{
    let res = File::read_string("/proc/cpuinfo");
    if(res.is_err()){
        return 4;
    }
    let txt = res.unwrap();
    let lines = txt.split("\n");
    let n = 0;
    for line in &lines{
        if(line.starts_with("processor")){
            ++n;
        }
    }
    if(n > 8){
        n = 8;
    }
    if(n < 1){
        n = 4;
    }
    return n;
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
  let lib = Compiler::compile_dir(config)?;
  return lib;
}

func handle_c(cmd: CmdArgs*){
  //`c` is the default command: only consume the command word when present,
  //so `x hello.x` works like `x c hello.x`.
  if(cmd.is("c") || cmd.is("compile")){
    cmd.consume();
  }
  if(!cmd.has_any("-out")){
    print("missing required flag -out\n");
    print_usage();
    exit(1);
  }
  let out_dir = cmd.get_val2("-out");
  //deprecated no-op: builds never run the binary anymore, but scripts still
  //pass -norun so the same command works against pre-1.07 bootstrap compilers
  cmd.consume_any("-norun");
  let compile_only = cmd.consume_any("-nolink");
  let link_static = cmd.consume_any("-static");
  let link_shared = cmd.consume_any("-shared");
  let flags = cmd.get_val_or("-flags", "".str());
  //The standard library is linked by default; -nostd gets the old bare link
  //line. -std is still accepted (it used to be required) and does nothing.
  let link_std = !cmd.consume_any("-nostd");
  let name: Option<String> = cmd.get_val("-name");
  let out_name: Option<String> = cmd.get_val("-o");
  let jobs = cmd.get_val("-j");
  if(jobs.is_none()){
    //attached form: -j4
    for(let i = 0;i < cmd.args.len();++i){
      let a = cmd.args.get(i).str();
      if(a.starts_with("-j") && a.len() > 2){
        let num = a.substr(2, a.len());
        jobs.set(num.owned());
        cmd.args.remove(i);
        break;
      }
    }
  }
  let config = CompilerConfig::new();
  config.use_cache = cmd.consume_any("-cache");
  config.cache_write = !cmd.consume_any("-cache-ro");
  config.incremental_enabled = cmd.consume_any("-inc");
  config.debug = cmd.consume_any("-g");
  config.stack_trace = cmd.consume_any("-trace");
  let opt_levels = ["-O", "-O0", "-O1", "-O2", "-O3"];
  for level in opt_levels[0..opt_levels.len()]{
    if(cmd.consume_any(level)){
      config.opt_level = Option::new(level.owned());
      break;
    }
  }
  if(jobs.is_some()){
    config.set_jobs(i32::parse(jobs.get().str()).unwrap());
  }
  while(cmd.has_any("-i")){
    let dir: String = cmd.get_val("-i").unwrap();
    config.add_dir(dir);
  }
  //repeatable: -remap-path-prefix OLD=NEW. Replaces a source path prefix
  //before it is recorded (assert/panic literals, diagnostics, DWARF), so a
  //build directory can be kept out of the output.
  while(cmd.has_any("-remap-path-prefix")){
    let spec: String = cmd.get_val("-remap-path-prefix").unwrap();
    if(spec.str().indexOf("=") < 1){
      print("invalid -remap-path-prefix '{}': expected OLD=NEW\n", &spec);
      exit(1);
    }
    config.add_remap(spec);
  }
  if(cmd.has_any("-stdpath")){
    let std_path = cmd.get_val2("-stdpath");
    config.add_dir(std_path.clone());
    config.set_std(std_path.clone());
    cmd.consume_any("-std");
    //The standard library is linked by default. A toolchain ships
    //<dir>/{src/std, lib/std.a}, so `-stdpath <dir>/src` gets the prebuilt
    //archive (no ar needed); a source tree has none, and <stdpath>/std is
    //built into the out dir instead (cached there, so only the first compile
    //per out dir pays). -nolink needs no archive at all.
    if(link_std && !compile_only){
      let prebuilt = format("{}/../lib/std.a", std_path);
      if(File::exists(prebuilt.str())){
        flags.append(" ");
        flags.append(prebuilt.str());
      }else{
        let lib = build_std(format("{}/std", std_path).str(), out_dir.str(), true);
        flags.append(" ");
        flags.append(lib.str());
      }
    }
  }else{
    //in <toolchain_dir>/{bin/x, src/std, lib/std.a}
    let binary = CmdArgs::get_root();
    let tool_dir = Path::parent(Path::parent(binary));
    let std_dir = format("{}/src", tool_dir);
    config.add_dir(std_dir.clone());
    config.set_std(std_dir);
    cmd.consume_any("-std");
    if(link_std && !compile_only){
      let prebuilt = format("{}/lib/std.a", tool_dir);
      //a toolchain ships lib/std.a next to bin/x; a bare compiler binary
      //(build/.../stage1) has none, so there is nothing to link
      if(File::exists(prebuilt.str())){
        flags.append(" ");
        flags.append(prebuilt.str());
      }
    }
  }
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

  if(!cmd.has()){
    print("missing input file\n");
    print_usage();
    exit(1);
  }
  let path: String = cmd.get()?;
  if(!File::exists(path.str())){
    print("no such file or directory: {}\n", &path);
    exit(1);
  }
  let name2: str = if(name.is_some()){
    name.get().str()
  }else{
    Path::name(path.str())
  };
  config.set_file(path.str());
  config.set_out(out_dir.clone());
  //A directory is compiled one file at a time, so run several files at once
  //by default. `-j N` still decides N explicitly and `-j 1` forces the serial
  //path; single-file compiles are unaffected (there is nothing to overlap).
  if(jobs.is_none() && File::is_dir(config.file.str())){
    config.set_jobs(cpu_count());
  }
  if(link_static){
    if(out_name.is_none()){
      out_name.set(format("{}.a", name2));
    }
    config.set_link(LinkType::Static{out_name.unwrap()});
  }else if(link_shared){
    if(out_name.is_none()){
      out_name.set(format("{}.so", name2));
    }    
    config.set_link(LinkType::Dynamic{out_name.unwrap()});
  }else if(compile_only){
    config.set_link(LinkType::None);
  }else{
    if(out_name.is_none()){
      out_name.set(name2.owned());
    }
    config.set_link(LinkType::Binary{out_name.unwrap(), flags});
  }
  
  if(File::is_dir(path.str())){
    let out = Compiler::compile_dir(config)?;
  }else{
    let out = Compiler::compile_single(config)?;
  }
  cmd.end();
}

func print_version(){
  print("{} version {} by {}\n", get_compiler_name(), get_version(), get_vendor());
}

func print_usage(){
  print("usage: x <command>\n");
  print("  c [-o name] [-out dir] [-stdpath dir] [-i dir]\n");
  print("    [-O0/-O1/-O2/-O3] [-nolink] [-static] [-shared] [-g]\n");
  print("    [-cache] [-cache-ro] [-inc] [-trace] [-flags '...']\n");
  print("    [-remap-path-prefix OLD=NEW]\n");
  print("    [-nostd] [-target x86_64|aarch64|android] <file.x|dir>\n");
  print("  -v, --version\n");
  print("  -h, --help\n");
}

func handle(cmd: CmdArgs*){
  let env_triple = std::getenv("target_triple");
  if(env_triple.is_some()){
    print("triple={}\n", env_triple.get());
  }

  if(!cmd.has()){
    print("enter a command\n");
    return;
  }
  if(cmd.is("-v") || cmd.is("--version")){
    print_version();
    return;
  }
  if(cmd.is("-h") || cmd.is("--help")){
    print_usage();
    return;
  }
  if(cmd.is("c") || cmd.is("compile")){
    handle_c(cmd);
    return;
  }else if(cmd.args.get(0).str().starts_with("-")){
    print("unknown command: {}\n", cmd.args.get(0));
    print_usage();
    exit(1);
  }else{
    //bare path: `x hello.x` means `x c hello.x`
    handle_c(cmd);
    return;
  }
}

func main(argc: i32, args: i8**){
  let cmd = CmdArgs::new(argc, args);
  handle(&cmd);
}
