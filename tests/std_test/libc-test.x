import std/libc
import std/io

func file_name(): str{
  return "./test.txt";
}

func read_test(){
  let path = file_name();
  let buf = read_bytes(path);
  assert(buf.len() == 5);
  let s = String::new(&buf);
  assert(s.eq("hello"));
}

func seek_test(f: FILE*){
  fseek(f, 0, SEEK_END());
  print("tell={}\n", ftell(f));
}

func write_test(){
  let buf = String::new("hello");
  let path = file_name();
  write_bytes(buf.slice(), path);
}

func list_test(){
  let dir = ".";
  let arr: List<String> = list(dir);
  print("{} files in '{}'\n", arr.len(), dir);
  /*for(let i = 0;i < arr.len();++i){
    let file = arr.get_ptr(i);
    print("{}\n", file.ptr());
  }*/
}

func main(){
  let cur = ".";
  print("pwd = {}\n", resolve(cur));
  write_test();
  read_test();
  list_test();
  print("libc_test done\n");
}