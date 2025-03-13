import std/libc
import std/io

func file_name(): str{
  return "./test.txt";
}

func read_test(){
  let path = file_name();
  let str = read_string(path);
  assert(str.len() == 5);
  assert(str.eq("hello"));
  str.drop();
}

func seek_test(f: FILE*){
  fseek(f, 0, SEEK_END());
  print("tell={}\n", ftell(f));
}

func write_test(){
  let str = String::new("hello");
  let path = file_name();
  write_bytes(str.slice(), path);
  str.drop();
}

func list_test(){
  let dir = ".";
  let arr: List<String> = list(dir);
  print("{} files in '{}'\n", arr.len(), dir);
  /*for(let i = 0;i < arr.len();++i){
    let file = arr.get_ptr(i);
    print("{}\n", file.ptr());
  }*/
  arr.drop();
}

func parse_float(){
  //let x = atof("3.14".ptr());
  //printf("x=%f\n", x);
}

func time_test(){
   let tp: timeval = timeval{0, 0};
   gettimeofday(&tp, ptr::null<i8>());
   print("time={:?} ms={}\n", tp, tp.ms());
}

func measure(){
    let tp: timeval = timeval{0, 0};
    gettimeofday(&tp, ptr::null<i8>());
    print("time1={:?} ms={}\n", tp, tp.ms());
    sleep(2);
    let end: timeval = timeval{0, 0};
    gettimeofday(&end, ptr::null<i8>());
    print("time2={:?} ms={}\n", end, end.ms());
    print("diff={:?} sec={}\n", end.ms() - tp.ms(), end.tv_sec-tp.tv_sec);
}

func main(){
  parse_float();
  let cur = resolve(".");
  print("pwd = {}\n", cur);
  cur.drop();
  write_test();
  read_test();
  list_test();
  time_test();
  measure();
  print("libc_test done\n");
}