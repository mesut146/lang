import std/map
import std/io
import std/libc
import std/stack
import std/any
import std/th

import ast/ast
import ast/printer
import ast/utils
import ast/copier

import resolver/resolver
import resolver/derive

import parser/cache
import parser/incremental

import backend/emitter


func get_linker(): str{
  let opt = std::getenv("LD");
  if(opt.is_some()){
    return opt.unwrap();
  }
  let arr = ["clang++-19", "clang++", "g++", "gcc"];
  for ld in &arr[0..arr.len()]{
    let res = Process::run(*ld).read_close();
    if(res.is_ok()){
      res.drop();
      return *ld;
    }
  }
  panic("can't find linker");
}

func get_ar(): str{
  let opt = std::getenv("AR");
  if(opt.is_some()){
    return opt.unwrap();
  }
  let arr = ["ar"];
  for ld in &arr[0..arr.len()]{
    let res = Process::run(*ld).read_close();
    if(res.is_ok()){
      res.drop();
      return *ld;
    }
  }
  panic("can't find AR");
}

struct CompilerError{
  msg: String;
}
impl CompilerError{
  func new(msg: String): CompilerError{
    return CompilerError{msg};
  }
}

enum LinkType{
  Binary{name: String, args: String, run: bool},
  Static{name: String},
  Dynamic{name: String},
  None
}

struct CompilerConfig{
  file: String;
  src_dirs: List<String>;
  out_dir: String;
  args: String;
  lt: LinkType;
  std_path: Option<String>;
  root_dir: Option<String>;
  jobs: i32;
  verbose_all: bool;
  incremental_enabled: bool;
  use_cache: bool;
  llvm_only: bool;
  debug: bool;
  opt_level: Option<String>;
  stack_trace: bool;
  inline_rvo: bool;
}
impl CompilerConfig{
  func new(): CompilerConfig{
    return CompilerConfig::new(Option<String>::new());
  }
  func new(std_path: String): CompilerConfig{
    return CompilerConfig::new(Option<String>::new(std_path));
  }
  func new(std_path: Option<String>): CompilerConfig{
    return CompilerConfig{
      file: "".str(),
      src_dirs: List<String>::new(),
      out_dir: "".str(),
      args: "".str(),
      lt: LinkType::None,
      std_path: std_path,
      root_dir: Option<String>::new(),
      jobs: 0,
      verbose_all: false,
      incremental_enabled: false,
      use_cache: true,
      llvm_only: false,
      debug: false,
      opt_level: Option<String>::new(),
      stack_trace: false,
      inline_rvo: false,
    };
  }
}

func has_main(unit: Unit*): bool{
  for (let i = 0;i < unit.items.len();++i) {
    let it = unit.items.get(i);
    if let Item::Method(m) = it{
      if(is_main(m)){
        return true;
      }
    }
  }
  return false;
}

func get_out_file(path: str, out_dir: str): String{
  let name = getName(path);
  let res = format("{}/{}.o", out_dir, trimExtenstion(name));
  return res;
}

func trimExtenstion(name: str): str{
  let i = name.lastIndexOf(".");
  if(i == -1){
    return name;
  }
  return name.substr(0, i);
}

func getName(path: str): str{
  let i = path.lastIndexOf("/");
  return path.substr(i + 1);
}

struct Compiler;
impl Compiler{
  func compile_single(config: CompilerConfig): Result<String, CompilerError>{
    config.use_cache = false;
    File::create_dir(config.out_dir.str())?;
    let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
    for inc_dir in &config.src_dirs{
      ctx.add_path(inc_dir.str());
    }
    let cache = new_cache(&config);
    let cmp = Emitter::new(ctx, &config, &cache);
    let compiled = List<String>::new();
    if(cmp.ctx.verbose){
      print("compiling {}\n", config.trim_by_root(config.file.str()));
    }
    let obj = cmp.compile(config.file.str());
    compiled.add(obj);
    let res = config.link(&compiled);
    config.drop();
    cmp.drop();
    compiled.drop();
    cache.drop();
    return res;
  }

  func compile_dir(config: CompilerConfig): Result<String, CompilerError>{
    if(config.jobs > 0){
      return Compiler::compile_dir_thread(config);
    }
    File::create_dir(config.out_dir.str())?;
    let cache = new_cache(&config);
    cache.read_cache();
    
    let inc = Incremental::new(config.incremental_enabled, config.out_dir.str(), config.file.clone());
    let src_dir = &config.file;
    let list: List<String> = File::read_dir(src_dir.str()).unwrap();
    let compiled = List<String>::new();
    for(let i = 0;i < list.len();++i){
      let name = list.get(i).str();
      if(!name.ends_with(".x")) continue;
      let file: String = format("{}/{}", src_dir, name);
      if(File::is_dir(file.str())) {
        file.drop();
        continue;
      }
      let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
      ctx.verbose_all = config.verbose_all;
      for(let j = 0;j < config.src_dirs.len();++j){
        ctx.add_path(config.src_dirs.get(j).str());
      }
      let cmp = Emitter::new(ctx, &config, &cache);
      if(cmp.ctx.verbose){
        print("compiling [{}/{}] {}\n", i + 1, list.len(), config.trim_by_root(file.str()));
      }
      let obj = cmp.compile(file.str());
      compiled.add(obj);
      cmp.drop();
      file.drop();
    }
    for rec_file in &cache.inc.recompiles{
      let file: String = format("{}/{}", src_dir, rec_file);
      print("recompiling {}\n", config.trim_by_root(file.str()));
      //rem output to trigger recompiling
      File::remove_file(get_out_file(file.str(), config.out_dir.str()).str())?;
      let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
      ctx.verbose_all = config.verbose_all;
      for(let j = 0;j < config.src_dirs.len();++j){
        ctx.add_path(config.src_dirs.get(j).str());
      }
      let cmp = Emitter::new(ctx, &config, &cache);
      let obj = cmp.compile(file.str());
      //compiled.add(obj);
      cmp.drop();
      file.drop();
    }
    list.drop();
    cache.drop();
    inc.drop();
    return config.link(&compiled);
  }

  func new_cache(config: CompilerConfig*): Cache{
    return Cache::new(config.incremental_enabled, config.use_cache, config.out_dir.str(), config.file.clone());
  }
  
  func compile_dir_thread(config: CompilerConfig): Result<String, CompilerError>{
    File::create_dir(config.out_dir.str())?;
    let cache = new_cache(&config);
    cache.read_cache();
    let src_dir = &config.file;
    let list: List<String> = File::read_dir(src_dir.str()).unwrap();
    let compiled = Mutex::new(List<String>::new());
    let worker = Worker::new(config.jobs);
    for(let i = 0;i < list.len();++i){
      let name = list.get(i).str();
      let file: String = format("{}/{}", src_dir, name);
      if(File::is_dir(file.str()) || !name.ends_with(".x")) {
        file.drop();
        continue;
      }
      let idx = Mutex::new(0);
      let args = CompileArgs{
        file: file.clone(),
        config: &config,
        cache: &cache,
        compiled: &compiled,
        idx: &idx,
        len: list.len() as i32,
      };
      worker.add_arg(Compiler::make_compile_job, args);
    }
    sleep(1);
    worker.join();
    list.drop();
    cache.drop();
    let comp = compiled.unwrap();
    return config.link(&comp);
  }

  func make_compile_job(arg: c_void*){
    let args = arg as CompileArgs*;
    let config = args.config;
    let ctx = Context::new(config.out_dir.clone(), config.std_path.clone());
    for dir in &config.src_dirs{
      ctx.add_path(dir.str());
    }
    let cmd = format("{} c -out {} -stdpath {} -nolink -cache", root_exe.get(), args.config.out_dir, args.config.std_path.get());
    for inc_dir in &args.config.src_dirs{
        cmd.append(" -i ");
        cmd.append(inc_dir);
    }
    if(config.opt_level.is_some()){
      cmd.append(" ");
      cmd.append(config.opt_level.get());
    }
    cmd.append(" ");
    cmd.append(&args.file);
    if(ctx.verbose){
      let idx = args.idx.lock();
      print("compiling {}\n", config.trim_by_root(args.file.str()));
      *idx = *idx + 1;
      args.idx.unlock();
    }
    let proc = Process::run(cmd.str());
    let code = proc.eat_close();
    if(code != 0){
      panic("failed to compile {}", args.file);
    }
    if(ctx.verbose){
      let idx = args.idx.lock();
      let compiled = args.compiled.lock();
      print("compiled [{}/{}] {}\n", compiled.len() + 1, args.len, config.trim_by_root(args.file.str()));
      args.compiled.unlock();
      args.idx.unlock();
    }
    let compiled = args.compiled.lock();
    compiled.add(format("{}", get_out_file(args.file.str(), config.out_dir.str())));
    args.compiled.unlock();
    sleep(1);
    ctx.drop();
    cmd.drop();
  }

  func build_library(compiled: List<String>*, name: str, out_dir: str, is_shared: bool): Result<String, CompilerError>{
    File::create_dir(out_dir)?;
    let cmd = "".str();
    if(is_shared){
      cmd.append(get_linker());
      cmd.append("-shared -o ");
    }else{
      cmd.append(get_ar());
      cmd.append(" rcs ");
    }
    let out_file = format("{}/{}", out_dir, name);
    //print("linking {}\n", out_file);
    cmd.append(&out_file);
    cmd.append(" ");
    for file in compiled{
      cmd.append(file.str());
      cmd.append(" ");
    }

    let cmd_res = Process::run(cmd.str()).read_close();
    if(cmd_res.is_err()){
      let res = Result<String, CompilerError>::err(CompilerError::new(format("link failed '{}'\ncmd={}", cmd_res.get_err(), cmd)));
      cmd.drop();
      return res;
    }
    cmd_res.drop();
    print("build library {}\n", out_file);
    return Result<String, CompilerError>::ok(out_file);
  }
  
  func link(compiled: List<String>*, out_dir: str, name: str, args: str): Result<String, CompilerError>{
    let out_file = format("{}/{}", out_dir, name);
    //print("linking {}\n", out_file);
    if(File::exists(out_file.str())){
      File::remove_file(out_file.str())?;
    }
    File::create_dir(out_dir)?;
    let cmd = get_linker().str();
    cmd.append(" -o ");
    cmd.append(&out_file);
    cmd.append(" ");
    for obj_file in compiled{
      cmd.append(obj_file.str());
      cmd.append(" ");
    }
    cmd.append(args);
    //todo move this to main or bt.sh
    cmd.append(" -Wl,-rpath=$ORIGIN/../lib");
    File::write_string(cmd.str(), format("{}/link.sh", out_dir).str())?;
 
    let cmd_res = Process::run(cmd.str()).read_close();
    if(cmd_res.is_err()){
      return Result<String, CompilerError>::err(CompilerError::new(format("link failed '{}'\ncmd={}", cmd_res.get_err(), cmd)));
    }
    print("build binary {}\n", out_file);
    cmd.drop();
    return Result<String, CompilerError>::ok(out_file);
  }
  
  func run(path: String){
    let path_c: CStr = path.cstr();
    let code = system(path_c.ptr());
    if(code != 0){
      print("error while running {} code={}\n", path_c, code);
      exit(1);
    }
    path_c.drop();
  }
}//Compiler


struct CompileArgs{
  file: String;
  config: CompilerConfig*;
  cache: Cache*;
  compiled: Mutex<List<String>>*;
  idx: Mutex<i32>*;
  len: i32;
}

impl CompilerConfig{
  func set_std(self, std_path: String): CompilerConfig*{
    self.std_path.drop();
    self.std_path = Option::new(std_path);
    return self;
  }
  func set_std_path(self, std_path: str): CompilerConfig*{
    self.std_path.drop();
    self.std_path = Option::new(std_path.str());
    return self;
  }
  func set_out(self, out: str): CompilerConfig*{
    return self.set_out(out.str());
  }
  func set_out(self, out: String): CompilerConfig*{
    self.out_dir.drop();
    self.out_dir = out;
    return self;
  }
  func add_dir(self, dir: str): CompilerConfig*{
    self.src_dirs.add(dir.str());
    return self;
  }
  func add_dir(self, dir: String): CompilerConfig*{
    self.src_dirs.add(dir);
    return self;
  }
  func set_link(self, lt: LinkType): CompilerConfig*{
    self.lt = lt;
    return self;
  }
  func set_file(self, file: str): CompilerConfig*{
    return self.set_file(file.str());
  }
  func set_file(self, file: String): CompilerConfig*{
    self.file.drop();
    self.file = file;
    return self;
  }
  func set_jobs(self, j: i32): CompilerConfig*{
    if(j < 0){
      panic("invalid jobs {:?}", j);
    }
    self.jobs = j;
    return self;
  }
  func link(self, compiled: List<String>*): Result<String, CompilerError>{
    if(self.llvm_only) return Result<String, CompilerError>::ok("".owned());
    match &self.lt{
      LinkType::None => return Result<String, CompilerError>::ok("".owned()),
      LinkType::Binary(bin_name, args, run) => {
        let path = Compiler::link(compiled, self.out_dir.str(), bin_name.str(), args.str());
        if(path.is_ok() && *run){
          Compiler::run(path.get().clone());
        }
        return path;
      },
      LinkType::Static(lib_name) => {
        return Compiler::build_library(compiled, lib_name.str(), self.out_dir.str(), false);
      },
      LinkType::Dynamic(lib_name) => {
        return Compiler::build_library(compiled, lib_name.str(), self.out_dir.str(), true);
      },
    }
  }
  func trim_by_root(self, path: str): str{
    if(self.root_dir.is_none()){
      return path;
    }
    let root = self.root_dir.get();
    if(path.starts_with(root.str())){
      let res = path.substr(root.len());
      if(res.starts_with("/")){
        return res.substr(1, res.len());
      }
    }
    return path;
  }
}