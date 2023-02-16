import str
import List

class c_void{}
class FILE{}

//type char = i8
//type int i32

//const stdout = 0

func SEEK_END(): i32 { return 2; }
func SEEK_SET(): i32 { return 1; }

extern{
  func free(ptr: i8*);
  //func malloc(size: i64): i8*;
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

func read_bytes(path: str): List<i8>{
  let f = fopen(path.ptr(), "r".ptr());
  fseek(f, 0, SEEK_END());
  let size = ftell(f) as i32;
  fseek(f, 0, SEEK_SET());
  let res = List<i8>::new(size);
  let buf = [0 as i8; 1024];
  while(true){
      let rcnt = fread(&buf[0], 1, 1024, f);
      if(rcnt <= 0){ break; }
      res.add(buf[0..1024]);
  }
  return res;
}

func read_test(f: FILE*){
  let buf = [0 as i8; 1000];
  //let rcnt = fread(&buf[0], 1, 1000, f);
  //print("read=%d\n", rcnt);
  //print("str=%s\n", &buf[0]);
  
}

func seek_test(f: FILE*){
  fseek(f, 0, SEEK_END());
  print("tell=%d\n", ftell(f));
}

func libc_test(){
  let name = "./libc.ll";
  let mode = "r";
  
  let f = fopen(name.ptr(), mode.ptr());
  print("file=%p\n", f);
  //read_test(f);
  fclose(f);
}