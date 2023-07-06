import std/libc

func read_bytes(path: str): List<i8>{
  let f = fopen(path.cstr(), "r".cstr());
  if(!is_valid(f)){
    panic("no such file %s", path.cstr());
  }
  fseek(f, 0, SEEK_END());
  let size = ftell(f);
  //print("size = %lld\n", size);
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
  return String::new(read_bytes(path));
}

func write_bytes(data: List<i8>*, path: str){
  let f = fopen(path.cstr(), "w".cstr());
  let c = fwrite(data.arr, 1, data.len() as i32, f);
  print("wrote %d of %lld\n", c, data.len());
  fclose(f);
}

func dump(arr: [i8; 256], len: i32){
  for(let i=0;i<len;++i){
    print("%c", arr[i]);
  }
  print("\n");
}

func list(path: str): List<String>{
  let list = List<String>::new();
  let dp = opendir(path.cstr());
  if(dp as u64 == 0) panic("no such dir");
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
  let ptr = realpath(path.cstr(), &buf[0] as i8*);
  let len = strlen(buf[0..256]);
  return String::new(buf[0..len]);
}