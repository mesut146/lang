import std/libc

func open_checked(path: CStr*, mode: CStr*): FILE*{
  let f = fopen(path.ptr(), mode.ptr());
  if(!is_valid(f)){
    panic("no such file %s", path.ptr());
  }
  return f;
}

func read_bytes(path: CStr*): List<i8>{
  let mode = CStr::new("r");
  let f = open_checked(path, &mode);
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
  let data: List<i8> = read_bytes(path);
  return String::new(&data);
}

func write_bytes(data: [u8], path: CStr*){
  let mode = CStr::new("w");
  let f = open_checked(path, &mode);
  let c = fwrite(data.ptr() as i8*, 1, data.len() as i32, f);
  print("wrote %d of %lld\n", c, data.len());
  fclose(f);
}

func dump_arr(arr: [i8; 256], len: i32){
  for(let i = 0;i < len;++i){
    print("%c", arr[i]);
  }
  print("\n");
}

/*func list(path: CStr*): List<String>{
  let list = List<String>::new(128);
  let dp = opendir(path.ptr());
  if(dp as u64 == 0) panic("no such dir %s", path.ptr());
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
  let list = List<CStr>::new(10);
  let dp = opendir(path.ptr());
  if(dp as u64 == 0) panic("no such dir %s", path.ptr());
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
  let dp = opendir(path.cstr().ptr());
  if(dp as u64 != 0){
    closedir(dp);
    return true;
  }
  return false;
}

func is_file(path: str): bool{
  let fp = fopen(path.cstr().ptr(), "r".cptr());
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

func resolve(path: CStr*): CStr{
  let buf = [0i8; 256];
  let ptr = realpath(path.ptr(), &buf[0] as i8*);
  if(ptr as u64 == 0){
    panic("resolving path is null '%s'\n", path.ptr());
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