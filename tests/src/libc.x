
class c_void{}
class FILE{}

//type char = i8
//type int i32

//const stdout = 0

func SEEK_END(): i32 { return 2; }
func SEEK_SET(): i32 { return 0; }

extern{
  func free(ptr: i8*);
  //func malloc(size: i64): i8*;
  func memcpy(dest: i8*, src: i8*, cnt: i32);
  func fopen(name: i8*, mode: i8*): FILE*;
  func fclose(file: FILE*): i32;
  func fflush(file: FILE*): i32;
  func fwrite(buf: i8*, size: i32, count: i32, target: FILE*): i32;
  func fread(buf: i8*, size: i32, count: i32, target: FILE*): i32;
  func fseek(file: FILE*, offset: i64, origin: i32): i32;
  func ftell(file: FILE*): i64;
  func remove(name: i8*): i32;
  func rename(old_name: i8*, new_name: i8*): i32;
}

func cstr(s: str): i8*{
    if(s.get(s.len())==0) return s.ptr();
    let buf = malloc(s.len() + 1);
    memcpy(buf, s.ptr(), s.len());
    buf[s.len()] = 0i8;
    return buf;
}

func read_bytes(path: str): List<i8>{
  let f = fopen(cstr(path), cstr("r"));
  fseek(f, 0, SEEK_END());
  let size = ftell(f);
  print("size = %lld\n", size);
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

func write_bytes(data: List<i8>, path: str){
  let f = fopen(cstr(path), cstr("w"));
  let c = fwrite(data.arr, 1, data.len() as i32, f);
  print("wrote %d of %lld\n", c, data.len());
  fclose(f);
}

func read_test(){
  let buf = read_bytes("./Box.ll");
  print("read %d\n", buf.len());
  //str{buf.slice(0, buf.len())}.dump();
}

func seek_test(f: FILE*){
  fseek(f, 0, SEEK_END());
  print("tell=%d\n", ftell(f));
}

func write_test(){
  let path = "./test.txt";
  //let buf = String::new("hello").arr;
  //write_bytes(buf.arr, path);
}

func main(){
  read_test();
  write_test();
  
  print("libc_test done\n");
}