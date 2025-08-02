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

import parser/compiler
import parser/debug_helper
import parser/llvm
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

func trim_nl(s: String): String{
  if(s.str().ends_with("\n")){
    return s.substr(0, s.len() - 1).owned();
  }
  return s;
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
  let jobs = cmd.get_val("-j");
  let config = CompilerConfig::new();
  config.use_cache = cmd.consume_any("-cache");
  config.incremental_enabled = cmd.consume_any("-inc");
  config.debug = cmd.consume_any("-g");
  config.stack_trace = cmd.consume_any("-trace");
  let opt_levels = ["-O", "O0", "-O1", "-O2", "-O3"];
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
  if(cmd.has_any("-stdpath")){
    let std_path = cmd.get_val2("-stdpath");
    //config.add_dir(Path::parent(std_path.str()).owned());
    config.add_dir(std_path.clone());
    config.set_std(std_path.clone());
    if(cmd.consume_any("-std")){
      let lib = build_std(std_path.str(), out_dir.str());
      flags.append(" ");
      flags.append(lib.str());
      lib.drop();
    }
    std_path.drop();
  }else{
    //in <toolchain_dir>/{bin/x, src/std, lib/std.a}
    let binary = CmdArgs::get_root();
    let tool_dir = Path::parent(Path::parent(binary));
    let std_dir = format("{}/src", tool_dir);
    config.add_dir(std_dir.clone());
    config.set_std(std_dir);
    if(cmd.consume_any("-std")){
      flags.append(format("{}/lib/std.a", tool_dir));
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

  let path: String = cmd.get()?;
  
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
    let out = Compiler::compile_dir(config)?;
    out.drop();
  }else{
    let out = Compiler::compile_single(config)?;
    out.drop();
  }
  path.drop();
  out_dir.drop();
  cmd.end();
}

func print_version(){
  print("{} version {} by {}\n", get_compiler_name(), get_version(), get_vendor());
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
  if(cmd.is("-v")){
    print_version();
    return;
  }
  if(cmd.is("c") || cmd.is("compile")){
    //todo should be default
    handle_c(cmd);
    return;
  }else{
    handle_c(cmd);
    return;
    //panic("invalid cmd: {:?}", cmd.args);
  }
}

func main(argc: i32, args: i8**){
  let cmd = CmdArgs::new(argc, args);
  handle(&cmd);
  cmd.drop();
}
