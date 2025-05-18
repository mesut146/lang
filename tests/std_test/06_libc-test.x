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
  printf("remove result=%d\n", remove(file_name.ptr()));
}

func seek_test(f: cFILE*, len: i32){
  fseek(f, 0, SEEK_END());
  assert(ftell(f) == len);
  fseek(f, 0, SEEK_SET());
}

func list_test(){
  let dir = ".";
  let arr: List<String> = File::read_dir(dir).unwrap();
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
   print("gettimeofday={:?} ms={}\n", tp, tp.as_ms());
}

func measure(){
    let begin: timeval = gettime();
    print("time1={:?} ms={}\n", begin, begin.as_ms());
    sleep(2);
    let end: timeval = gettime();
    let diff = end.sub(&begin);
    print("time2={:?} ms={}\n", end, end.as_ms());
    print("diff={:?} ms={}ms\n", diff, diff.as_ms());
}

func fork_test(){
  let pid = fork();
  print("pid={}\n", pid);
  if(pid == 0) {
      print("Child process\n");
  } else if(pid < 0) {
      print("Error: Failed to fork()\n");
  } else {
      print("Parent process\n");
  }
}

func main(){
  parse_float();
  let cur = File::resolve(".").unwrap();
  print("pwd = {}\n", cur);
  read_write();
  list_test();
  time_test();
  measure();
  fork_test();
  cur.drop();
  print("libc_test done\n");
}