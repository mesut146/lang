import std/libc

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