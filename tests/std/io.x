import std/libc

func open_checked(path: CStr*, mode: CStr*): FILE*{
  let f = fopen(path.ptr(), mode.ptr());
  if(!is_valid(f)){
    panic("no such file {}", path);
  }
  return f;
}

func read_bytes(path: CStr*): List<u8>{
  let mode = CStr::new("r");
  let f = open_checked(path, &mode);
  Drop::drop(mode);
  fseek(f, 0, SEEK_END());
  let size = ftell(f);
  fseek(f, 0, SEEK_SET());
  let res = List<u8>::new(size);
  let buf = [0u8; 1024];
  while(true){
      let rcnt = fread(&buf[0], 1, 1024, f);
      if(rcnt <= 0){ break; }
      res.add(buf[0..rcnt]);
  }
  fclose(f);
  return res;
}

func read_bytes_i8(path: CStr*): List<i8>{
  let mode = CStr::new("r");
  let f = open_checked(path, &mode);
  Drop::drop(mode);
  fseek(f, 0, SEEK_END());
  let size = ftell(f);
  fseek(f, 0, SEEK_SET());
  let res = List<i8>::new(size);
  let buf = [0i8; 1024];
  while(true){
      let rcnt = fread(&buf[0], 1, 1024, f);
      if(rcnt <= 0){ break; }
      res.add(buf[0..rcnt]);
  }
  fclose(f);
  return res;
}

func read_string(path: CStr*): String{
  let data: List<u8> = read_bytes(path);
  return String::new(data);
}

func write_bytes(data: [u8], path: CStr*){
  let mode = CStr::new("w");
  let f = open_checked(path, &mode);
  let cnt = fwrite(data.ptr() as i8*, 1, data.len() as i32, f);
  print("wrote {} of {}\n", cnt, data.len());
  fclose(f);
  Drop::drop(mode);
  if(cnt != data.len()){
    panic("didn!t write all");
  }
}

/*func list(path: CStr*): List<String>{
  let list = List<String>::new(128);
  let dp = opendir(path.ptr());
  if(dp as u64 == 0) panic("no such dir {}", path);
  while(true){
    let ep = readdir(dp);
    if(ep as u64 == 0) break;
    let entry = str::new(ep.d_name[0..ep.len()]);
    list.add(entry.str());
  }
  closedir(dp);
  return list;
}*/

func listc(path: CStr*): List<CStr>{
  let list = List<CStr>::new();
  let dp = opendir(path.ptr());
  if(dp as u64 == 0){
    panic("no such dir {}", path);
  }
  while(true){
    let ep = readdir(dp);
    if(ep as u64 == 0) break;
    let name: [u8] = ep.d_name[0..ep.len() + 1];//+1 for \0
    list.add(CStr::new(name));
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

func resolve(path: CStr*): CStr{
  let buf = [0i8; 256];
  let ptr = realpath(path.ptr(), &buf[0] as i8*);
  if(ptr as u64 == 0){
    panic("resolving path is null '{}'\n", path);
  }
  let len = strlen(buf[0..256]);
  let slice = buf[0..len + 1];
  return CStr::new(slice);
}

#derive(Drop)
struct Path{
  path: String;
}

impl Path{
  func new(path: String): Path{
    return Path{path: path};
  }
  func ext(self): str{
    let i = self.path.str().lastIndexOf(".");
    return self.path.substr(i + 1);
  }

  func name(self): str{
    let i = self.path.str().lastIndexOf("/");
    return self.path.substr(i + 1);
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
  //let sl = a1[0..len];
  return str::new(a1[0..len]);
}