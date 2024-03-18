import std/libc

func open_checked(path: str, mode: str): FILE*{
  let f = fopen(path.cstr(), mode.cstr());
  if(!is_valid(f)){
    panic("no such file %s", path.cstr());
  }
  return f;
}

func read_bytes(path: str): List<i8>{
  let f = open_checked(path, "r");
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

func read_string(path: str): String{
  let data = read_bytes(path);
  return String::new(&data);
}

func write_bytes(data: [u8], path: str){
  let f = open_checked(path, "w");
  let c = fwrite(data.ptr() as i8*, 1, data.len() as i32, f);
  print("wrote %d of %lld\n", c, data.len());
  fclose(f);
}

func dump(arr: [i8; 256], len: i32){
  for(let i = 0;i < len;++i){
    print("%c", arr[i]);
  }
  print("\n");
}

func list(path: str): List<String>{
  let list = List<String>::new();
  let dp = opendir(path.cstr());
  if(dp as u64 == 0) panic("no such dir %s", path.cstr());
  while(true){
    let ep = readdir(dp);
    if(ep as u64 == 0) break;
    let s = str::new(ep.d_name[0..ep.len()]);
    list.add(s.str());
  }
  closedir(dp);
  return list;
}

func is_dir(path: str): bool{
  let dp = opendir(path.cstr());
  if(dp as u64 != 0){
    closedir(dp);
    return true;
  }
  return false;
}

func is_file(path: str): bool{
  let fp = fopen(path.cstr(), "r".cstr());
  if(fp as u64 != 0){
    fclose(fp);
    return true;
  }
  return false;
}

func is_valid(fp: FILE*): bool{
  return fp as u64 != 0;
}

func exist(path: str): bool{
  return is_file(path) || is_dir(path);
}

func resolve(path: str): String{
  let buf = [0i8; 256];
  let path_c = path.cstr();
  let ptr = realpath(path_c, &buf[0] as i8*);
  if(ptr as u64 == 0){
    panic("resolving path is null '%s'\n", path_c);
  }
  let len = strlen(buf[0..256]);
  return String::new(buf[0..len]);
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