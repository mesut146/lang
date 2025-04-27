
import std/libc
import std/result

struct File{
  fp: cFILE*;
}

impl Drop for File{
  func drop(*self){
    fclose(self.fp);
  }
}

struct Permissions{
  mode: i32;
}

impl Permissions{
  //todo add more ctor
  func from_mode(val: i32): Permissions{
    return Permissions{
      val,
    };
  }
}

enum OpenMode{
  Read,
  Write,
  ReadWrite,
  Append,
}
impl OpenMode{
  func from(s: str): Result<OpenMode, String>{
    if(s.eq("r")) return Result<OpenMode, String>::ok(OpenMode::Read);
    if(s.eq("w")) return Result<OpenMode, String>::ok(OpenMode::Write);
    if(s.eq("rw")) return Result<OpenMode, String>::ok(OpenMode::ReadWrite);
    if(s.eq("a")) return Result<OpenMode, String>::ok(OpenMode::Append);
    return Result<OpenMode, String>::err(format("invalid mode {}", s));
  }
  func as_c_str(self): i8*{
    match self{
      //because str literals are consts this works without dropping
      OpenMode::Read => return "r".ptr(),
      OpenMode::Write => return "w".ptr(),
      OpenMode::ReadWrite => return "rw".ptr(),
      OpenMode::Append => return "a".ptr(),
    }
  }
}

impl File{
  func open(path: str, mode: OpenMode): Result<File, String>{
    let path_c = CStr::new(path);
    let fp = fopen(path_c.ptr(), mode.as_c_str());
    path_c.drop();
    if(fp as u64 == 0){
      return Result<File, String>::err(format("no such file '{}'", path));
    }
    return Result<File, String>::ok(File{fp});
  }

  func create(path: str): Result<File, String>{
    let path_c = CStr::new(path);
    let fp = fopen(path_c.ptr(), "w".cptr());
    if(fp as u64 == 0){
      return Result<File, String>::err(format("failed to create file '{}'", path));
    }
    Drop::drop(path_c);
    return Result<File, String>::ok(File{fp});
  }

  func close(*self){
    fclose(self.fp);
  }

  func remove_file(path: str): Result<(), String>{
    let path_c = CStr::new(path);
    let code = remove(path_c.ptr());
    path_c.drop();
    if(code == 0){
      return Result<(), String>::ok(());
    }
    return Result<(), String>::err(format("failed to remove file '{}'", path));
  }

  func copy(from: str, to: str): Result<(), String>{
    let src_file = File::open(from, OpenMode::Read)?;
    let target_file = File::open(to, OpenMode::Write)?;
    let bytes = src_file.read_bytes();
    target_file.write_bytes(bytes.slice())?;
    src_file.close();
    target_file.close();
    bytes.drop();
    return Result<(), String>::ok(());
  }

  func read_bytes(self): List<u8>{
    fseek(self.fp, 0, SEEK_END());
    let size = ftell(self.fp);
    fseek(self.fp, 0, SEEK_SET());
    let res = List<u8>::new(size);
    let buf = [0u8; 1024];
    while(true){
        let rcnt = fread(&buf[0], 1, 1024, self.fp);
        if(rcnt <= 0){ break; }
        res.add_slice(buf[0..rcnt]);
    }
    return res;
  }

  func read_string(self): String{
    let data: List<u8> = self.read_bytes();
    return String::new(data);
  }

  func read_string(path: str): Result<String, String>{
    let f = File::open(path, OpenMode::Read)?;
    let res = f.read_string();
    f.drop();
    return Result<String, String>::ok(res);
  }

  func write_bytes(self, data: [u8]): Result<(), String>{
    let cnt = fwrite(data.ptr() as i8*, 1, data.len() as i32, self.fp);
    if(cnt != data.len()){
      return Result<(), String>::err("didn't write all data to file".owned());
    }
    return Result<(), String>::ok(());
  }
  
  func write_string(data: str, path: str): Result<(), String>{
    return write_string(data, path, OpenMode::Write);
  }

  func write_string(data: str, path: str, mode: OpenMode): Result<(), String>{
    let file = File::open(path, mode)?;
    file.write_bytes(data.slice())?;
    file.close();
    return Result<(), String>::ok(());
  }

  func read_dir(path: str): Result<List<String>, String>{
    let list = List<String>::new();
    let path_c = CStr::new(path);
    let dp = opendir(path_c.ptr());
    path_c.drop();
    if(dp as u64 == 0) {
      return Result<List<String>, String>::err(format("no such dir {}", path));
    }
    while(true){
      let ep: dirent* = readdir(dp);
      if(ep as u64 == 0) break;
      let entry = str::new(ep.d_name[0..ep.len()]);
      list.add(entry.str());
    }
    closedir(dp);
    return Result<List<String>, String>::ok(list);
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
  
  /*func is_valid(fp: cFILE*): bool{
    return fp as u64 != 0;
  }*/

  func exists(path: str): bool{
    return is_file(path) || is_dir(path);
  }
  
  func create_dir(path: str): Result<(), String>{
    if(exists(path)){
      return Result<(), String>::ok(());
    }
    let path_c = CStr::new(path);
    let rc = mkdir(path_c.ptr(), /*0777*/ /*511*/ 511);
    Drop::drop(path_c);
    if(rc != 0){
      return Result<(), String>::err(format("failed to create dir '{}', code={}", path, &rc));
    }
    return Result<(), String>::ok(());
  }
  
  func resolve(path: str): Result<String, String>{
    let buf = [0i8; 256];
    let path_c = CStr::new(path);
    let ptr = realpath(path_c.ptr(), &buf[0] as i8*);
    Drop::drop(path_c);
    if(ptr as u64 == 0){
      return Result<String, String>::err(format("resolving path is null '{}'\n", path));
    }
    let len = strlen(buf.ptr(), buf.len() as i32);
    let slice = buf[0..len];
    return Result<String, String>::ok(String::new(slice));
  }

  func set_permissions(file: str, perm: Permissions): Result<(), String>{
    let filec = CStr::new(file);
    let fd = open(filec.ptr(), O_RDWR, 0);
    let ret = fchmod(fd, perm.mode);
    if(ret != 0){
      return Result<(), String>::err(format("failed to set permissions for '{}', code={}", file, ret));
    }
    Drop::drop(filec);
    return Result<(), String>::ok(());
  }
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

  func concat(path: str, name: str): String{
    if(path.ends_with("/")){
      path = path.substr(0, path.len() - 1);
    }
    return format("{}/{}", path, name);
  }
}