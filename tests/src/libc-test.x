import std/libc
import std/io

func read_test(){
  let buf = read_bytes("./libc-test.ll");
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

func list_test(){
  let dir = ".";
  list(dir);
}

func main(){
  read_test();
  write_test();
  list_test();
  print("res=%s\n", resolve(".").cstr());
  print("libc_test done\n");
}