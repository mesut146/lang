import std/libc

struct File;

impl File{
  func remove_file(path: str){
    let path_c = CStr::from_slice(path);
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
  let path_c = CStr::from_slice(path);
  let mode_c = CStr::from_slice(mode);
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

func list(path: str): List<String>{
  let list = List<String>::new(128);
  let path_c = CStr::from_slice(path);
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
  let path_c = CStr::from_slice(path);
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
  let path_c = CStr::from_slice(path);
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
  let path_c = CStr::from_slice(path);
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
  let path_c = CStr::from_slice(path);
  let rc = mkdir(path_c.ptr(), /*0777*/ /*511*/ 511);
  Drop::drop(path_c);
  if(rc != 0){
    print("code='{}'\n", rc);
    panic("failed to create dir '{}', code={}", path, &rc);
  }
}

func resolve(path: str): String{
  let buf = [0i8; 256];
  let path_c = CStr::from_slice(path);
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
}


func get_arg(args: i8**, idx: i32): str{
  let a1 = *ptr::get(args, idx) as u8*;
  if(a1 as u64 == 0){
    panic("null");
  }
  let len = strlen(a1 as i8*, 1000);
  return str::new(a1[0..len]);
}

struct CmdArgs{
  args: List<String>;
}

impl CmdArgs{
  func new(argc: i32, args: i8**): CmdArgs{
    let res = CmdArgs{args: List<String>::new()};
    for(let i = 1; i < argc;++i){
      let a1 = *ptr::get(args, i) as u8*;
      if(a1 as u64 == 0){
        panic("null");
      }
      let len = strlen(a1 as i8*, 1000);
      res.args.add(str::new(a1[0..len]).str());
    }
    return res;
  }
  func get(self): String{
    let res = self.args.remove(0);
    return res;
  }
  func has(self): bool{
    return self.args.len() > 0;
  }
}