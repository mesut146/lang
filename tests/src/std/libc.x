class c_void{}
class FILE{}
class DIR{}
struct dirent {
    d_ino: ino_t          ;       /* inode number */
    d_off: off_t          ;       /* offset to the next dirent */
    d_reclen: u16 ;    /* length of this record */
    d_type: u8  ;      /* type of file; not supported
                                   by all file system types */
    d_name: [u8; 256]; /* filename */
}

impl dirent{
  func len(self): i32{
    for(let i=0;i<256;++i){
      if(self.d_name[i]==0) return i;
    }
    panic("no eof");
  }
  func cstr(self): [u8]{
    return self.d_name[0..self.len()];
  }
}

func strlen(arr: [i8]): i32{
  for(let i = 0;i < arr.len();++i){
    if(arr[i] == 0) return i;
  }
  panic("no eof");
}
func strlen(arr: i8*, max: i32): i32{
  for(let i = 0;i < max;++i){
    if(*ptr::get(arr, i) == 0) return i;
  }
  panic("no eof");
}

func is_null<T>(ptr: T*): bool{
  return ptr as u64 == 0;
}

//type char = i8
//type int i32
type ino_t = u64;
type off_t = u64;

//const stdout = 0

func SEEK_END(): i32 { return 2; }
func SEEK_SET(): i32 { return 0; }

extern{
  func free(ptr: u8*);
  //func malloc(size: i64): i8*;
  func memcpy(dest: i8*, src: i8*, cnt: i32);
  func fopen(name: i8*, mode: i8*): FILE*;
  func fclose(file: FILE*): i32;
  //func fflush(file: FILE*): i32;
  func fwrite(buf: i8*, size: i32, count: i32, target: FILE*): i32;
  func fread(buf: i8*, size: i32, count: i32, target: FILE*): i32;
  func fseek(file: FILE*, offset: i64, origin: i32): i32;
  func ftell(file: FILE*): i64;
  func remove(name: i8*): i32;
  func rename(old_name: i8*, new_name: i8*): i32;
  func opendir(dir: i8*): DIR*;
  func readdir(dp: DIR*): dirent*;
  func closedir(dp: DIR*): i32;
  func realpath(path: i8*, resolved: i8*): i8*;
  func system(cmd: i8*): i32;
}



