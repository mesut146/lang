import std/libc

struct File;

impl File{
  func remove_file(path: str){
    let path_c = CStr::new(path);
    remove(path_c.ptr());
    path_c.drop();
  }
  func copy(from: str, to: str): bool{
    let data = read_bytes(from);
    write_bytes(data.slice(), to);
    data.drop();
    return true;
  }
}

func open_checked(path: str, mode: str): FILE*{
  let path_c = CStr::new(path);
  let mode_c = CStr::new(mode);
  let f = fopen(path_c.ptr(), mode_c.ptr());
  path_c.drop();
  mode_c.drop();
  if(!is_valid(f)){
    panic("no such file {}", path);
  }
  return f;
}

func read_bytes(path: str): List<u8>{
  let f = open_checked(path, "r");
  fseek(f, 0, SEEK_END());
  let size = ftell(f);
  fseek(f, 0, SEEK_SET());
  let res = List<u8>::new(size);
  let buf = [0u8; 1024];
  while(true){
      let rcnt = fread(&buf[0], 1, 1024, f);
      if(rcnt <= 0){ break; }
      res.add_slice(buf[0..rcnt]);
  }
  fclose(f);
  return res;
}

func read_bytes_i8(path: str): List<i8>{
  let f = open_checked(path, "r");
  fseek(f, 0, SEEK_END());
  let size = ftell(f);
  fseek(f, 0, SEEK_SET());
  let res = List<i8>::new(size);
  let buf = [0i8; 1024];
  while(true){
      let rcnt = fread(&buf[0], 1, 1024, f);
      if(rcnt <= 0){ break; }
      res.add_slice(buf[0..rcnt]);
  }
  fclose(f);
  return res;
}

func read_string(path: str): String{
  let data: List<u8> = read_bytes(path);
  return String::new(data);
}

func write_bytes(data: [u8], path: str){
  let f = open_checked(path, "w");
  let cnt = fwrite(data.ptr() as i8*, 1, data.len() as i32, f);
  fclose(f);
  if(cnt != data.len()){
    panic("didn't write all");
  }
}
func write_string(data: str, path: str){
  write_bytes(data.slice(), path);
}

func list(path: str, ext: Option<str>, file_only: bool): List<String>{
  let list = List<String>::new();
  let path_c = CStr::new(path);
  let dp = opendir(path_c.ptr());
  path_c.drop();
  if(dp as u64 == 0) panic("no such dir {}", path);
  while(true){
    let ep: dirent* = readdir(dp);
    if(ep as u64 == 0) break;
    let name = ep.str();
    if(ext.is_some() && name.ends_with(*ext.get())){
      if(file_only){
        let full_path = format("{}/{}", path, name);
        if(is_file(full_path.str())){
          list.add(name.str());
        }
        full_path.drop();
      }else{
        list.add(name.str());
      }
    }
  }
  closedir(dp);
  return list;
}
func list(path: str): List<String>{
  let list = List<String>::new();
  let path_c = CStr::new(path);
  let dp = opendir(path_c.ptr());
  path_c.drop();
  if(dp as u64 == 0) panic("no such dir {}", path);
  while(true){
    let ep: dirent* = readdir(dp);
    if(ep as u64 == 0) break;
    let entry = str::new(ep.d_name[0..ep.len()]);
    list.add(entry.str());
  }
  closedir(dp);
  return list;
}

func is_dir(path: str): bool{
  let path_c = CStr::new(path);
  let dp = opendir(path_c.ptr());
  if(dp as u64 != 0){
    closedir(dp);
    Drop::drop(path_c);
    return true;
  }
  Drop::drop(path_c);
  return false;
}

func is_file(path: str): bool{
  let path_c = CStr::new(path);
  let fp = fopen(path_c.ptr(), "r".cptr());
  if(fp as u64 != 0){
    fclose(fp);
    Drop::drop(path_c);
    return true;
  }
  Drop::drop(path_c);
  return false;
}

func is_valid(fp: FILE*): bool{
  return fp as u64 != 0;
}

func exist(path: str): bool{
  return is_file(path) || is_dir(path);
}

func create_file(path: str){
  let path_c = CStr::new(path);
  let fp = fopen(path_c.ptr(), "w".cptr());
  if(fp as u64 != 0){
    fclose(fp);
  }
  Drop::drop(path_c);
}

func create_dir(path: str){
  if(exist(path)){
    return;
  }
  let path_c = CStr::new(path);
  let rc = mkdir(path_c.ptr(), /*0777*/ /*511*/ 511);
  Drop::drop(path_c);
  if(rc != 0){
    print("code='{}'\n", rc);
    panic("failed to create dir '{}', code={}", path, &rc);
  }
}

func resolve(path: str): String{
  let buf = [0i8; 256];
  let path_c = CStr::new(path);
  let ptr = realpath(path_c.ptr(), &buf[0] as i8*);
  Drop::drop(path_c);
  if(ptr as u64 == 0){
    panic("resolving path is null '{}'\n", path);
  }
  let len = strlen(buf[0..256]);
  let slice = buf[0..len];
  return String::new(slice);
}

struct Path{
  path: String;
}

impl Path{
  func new(path: String): Path{
    return Path{path: path};
  }
  func new(path: str): Path{
    return Path{path: path.str()};
  }
  func ext(self): str{
    return Path::ext(self.path.str());
  }

  func ext(path: str): str{
    let name = Path::name(path);
    let i = name.lastIndexOf(".");
    if(i == -1){
      return name;
    }
    return name.substr(i + 1);
  }

  func name(self): str{
    return Path::name(self.path.str());
  }

  func name(path: str): str{
    let i = path.lastIndexOf("/");
    if(i == -1){
      return path;
    }
    return path.substr(i + 1);
  }

  func noext(self): str{
    let i = self.name().lastIndexOf(".");
    return self.path.substr(0, i);
  }
  func noext(path: str): str{
    let i = path.lastIndexOf(".");
    if(i == -1){
      return path;
    }
    return path.substr(0, i);
  }
  func parent(path: str): str{
    let i = path.lastIndexOf("/");
    if(i == -1){
      return "/";
    }
    return path.substr(0, i);
  }
}


struct CmdArgs{
  args: List<String>;
  root: String;
}

impl CmdArgs{
  func get_arg(args: i8**, idx: i32): str{
    let ptr = *ptr::get(args, idx) as u8*;
    if(ptr as u64 == 0){
      panic("ptr is null");
    }
    let len = strlen(ptr as i8*, 1000);
    return str::new(ptr[0..len]);
  }
  func new(argc: i32, args: i8**): CmdArgs{
    let root = CmdArgs::get_arg(args, 0).str();
    let res = CmdArgs{args: List<String>::new(), root: root};
    for(let i = 1; i < argc;++i){
      res.args.add(CmdArgs::get_arg(args, i).str());
    }
    return res;
  }
  func get_root(self): str{
    return self.root.str();
  }
  func consume(self){
    let arg = self.get();
    arg.drop();
  }
  func peek(self): String*{
    return self.args.get_ptr(0);
  }
  func get(self): String{
    if(self.args.len() == 0){
      panic("no more arguments");
    }
    let res = self.args.remove(0);
    return res;
  }
  func has(self): bool{
    return self.args.len() > 0;
  }
  func is(self, arg: str): bool{
    return self.args.get_ptr(0).eq(arg);
  }

  func has_any(self, arg: str): bool{
    for(let i = 0; i < self.args.len(); ++i){
      if(self.args.get_ptr(i).eq(arg)){
        return true;
      }
    }
    return false;
  }
  func consume_any(self, arg: str): bool{
    for(let i = 0; i < self.args.len(); ++i){
      if(self.args.get_ptr(i).eq(arg)){
        let tmp = self.args.remove(i);
        tmp.drop();
        return true;
      }
    }
    return false;
  }
  func get_val(self, arg: str): Option<String>{
    for(let i = 0; i < self.args.len(); ++i){
      if(self.args.get_ptr(i).eq(arg)){
        let val = self.args.remove(i + 1);
        let key = self.args.remove(i);
        key.drop();
        return Option::new(val);
      }
    }
    return Option<String>::new();
  }
  func get_val_or(self, arg: str, def: String): String{
    let val = self.get_val(arg);
    return val.unwrap_or(def);
  }
  func get_val2(self, arg: str): String{
    let val = self.get_val(arg);
    if(val.is_none()){
      panic("expected arg and val: {}", arg);
    }
    return val.unwrap();
  }
}