import std/libc
import std/io
import std/fs

func file_name(): str{
    return "./test.txt";
}

func read_test(){
  let path = file_name();
  let str = File::read_string(path)?;
  assert(str.len() == 5);
  assert(str.eq("hello"));
  str.drop();
}

func write_test(){
  let str = String::new("hello");
  let file = File::create(file_name())?;
  file.write_bytes(str.slice())?;
  str.drop();
  file.close();
}

func main(){
    write_test();
    read_test();
}