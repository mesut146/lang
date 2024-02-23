import std/libc
import std/io

func file_name(): str{
  return "./test.txt";
}

func read_test(){
  let buf = read_bytes(file_name());
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
  write_bytes(buf.slice(), file_name());
}

func list_test(){
  let dir = ".";
  list(dir);
}

func main(){
  print("pwd = %s\n", resolve(".").cstr());
  write_test();
  read_test();
  list_test();
  print("libc_test done\n");
}