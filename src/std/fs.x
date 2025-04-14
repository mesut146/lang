
import std/libc

struct File;

struct Permissions{
  mode: i32;
}

impl Permissions{
  func from_mode(val: i32): Permissions{
    return Permissions{
      val,
    };
  }
}

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
    if(dp as u64 == 0) panic("no such dir '{}'", path);
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
  
  /*func is_valid(fp: FILE*): bool{
    return fp as u64 != 0;
  }*/
  
  //todo deprecated
  func exist(path: str): bool{
    return is_file(path) || is_dir(path);
  }

  func exists(path: str): bool{
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
    let len = strlen(buf.ptr(), buf.len() as i32);
    let slice = buf[0..len];
    return String::new(slice);
  }

  func set_permissions(file: str, perm: Permissions){
    let filec = CStr::new(file);
    let fd = open(filec.ptr(), O_RDWR, 0);
    let ret = fchmod(fd, perm.mode);
    if(ret != 0){
      panic("failed to set permissions for '{}', code={}", file, ret);
    }
    Drop::drop(filec);
  }
}

func open_checked(path: str, mode: str): FILE*{
  let path_c = CStr::new(path);
  let mode_c = CStr::new(mode);
  let fp = fopen(path_c.ptr(), mode_c.ptr());
  path_c.drop();
  mode_c.drop();
  if(fp as u64 == 0){
    panic("no such file '{}'", path);
  }
  return fp;
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

  func relativize(path: str, parent: str): str{
    if(path.starts_with(parent)){
      let start = parent.len() + 1;
      if(start < path.len() && path.get(start) == '/'){
        start += 1;
      }
      return path.substr(start);
    }
    return path;
  }
}