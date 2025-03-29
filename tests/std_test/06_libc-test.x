import std/libc
import std/io
import std/fs

func file_name(): str{
  return "./test.txt";
}

func read_write(){
  let file_name = file_name();
  let fp = fopen(file_name.ptr(), "w+".ptr());
  if(is_null(fp)){
    panic("Error opening file '{}'\n", file_name);
  }
  let s = "hello";
  fwrite(s.ptr(), 1, 5, fp);
  seek_test(fp, 5);
  let buf = [0i8; 5];
  let read_cnt = fread(buf.ptr(), 1, 5, fp);
  assert(read_cnt == 5);
  assert(strcmp(buf.ptr(), s.ptr()) == 0);

  fclose(fp);
  remove(file_name.ptr());
}

func seek_test(f: FILE*, len: i32){
  fseek(f, 0, SEEK_END());
  assert(ftell(f) == len);
  fseek(f, 0, SEEK_SET());
}

func list_test(){
  let dir = ".";
  let arr: List<String> = File::list(dir);
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
  let cur = File::resolve(".");
  print("pwd = {}\n", cur);
  read_write();
  list_test();
  time_test();
  measure();
  print("libc_test done\n");
  cur.drop();
}