import std/libc
import std/io

func file_name(): CStr{
  return CStr::new("./test.txt");
}

func read_test(){
  let path = file_name();
  let buf = read_bytes(&path);
  assert buf.len() == 5;
  let s = String::new(&buf);
  assert s.eq("hello");
}

func seek_test(f: FILE*){
  fseek(f, 0, SEEK_END());
  print("tell=%d\n", ftell(f));
}

func write_test(){
  let buf = String::new("hello");
  let path = file_name();
  write_bytes(buf.slice(), &path);
}

func list_test(){
  let dir: CStr = CStr::new(".");
  let arr: List<CStr> = listc(&dir);
  print("%d files in '%s'\n", arr.len(), dir.ptr());
  /*for(let i = 0;i < arr.len();++i){
    let file = arr.get_ptr(i);
    print("%s\n", file.ptr());
  }*/
}

func main(){
  let cur = CStr::new(".");
  print("pwd = %s\n", resolve(&cur).ptr());
  write_test();
  read_test();
  list_test();
  print("libc_test done\n");
}