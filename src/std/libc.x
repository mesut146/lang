//type char = i8
//type int i32
type ino_t = u64;
type off_t = u64;

struct c_void;
struct FILE;
struct DIR;

struct dirent {
    d_ino: ino_t;      /* inode number */
    d_off: off_t;      /* offset to the next dirent */
    d_reclen: u16 ;    /* length of this record */
    d_type: u8;        /* type of file; not supported by all file system types */
    d_name: [u8; 256]; /* filename */
}

impl dirent{
  func len(self): i32{
    for(let i = 0;i < 256;++i){
      if(self.d_name[i] == 0) return i;
    }
    panic("no eof");
  }
  func str(self): str{
    return str::new(self.d_name[0..self.len()]);
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
func strlen(ptr: i8*): i32{
  return strlen(ptr, 100000);
}

func is_null<T>(ptr: T*): bool{
  return ptr as u64 == 0;
}

func SEEK_END(): i32 { return 2; }
func SEEK_SET(): i32 { return 0; }

func getenv2(name: str): Option<str>{
  let c_name = CStr::new(name);
  let c_env = getenv(c_name.ptr());
  c_name.drop();
  if(is_null(c_env)){
    return Option<str>::new();
  }
  return Option::new(str::from_raw(c_env));
}
func setenv2(name: str, val: str, overwrite: i32){
  let c_name = CStr::new(name);
  let c_val = CStr::new(val);
  setenv(c_name.ptr(), c_val.ptr(), overwrite);
  c_name.drop();
  c_val.drop();
}

extern{
  //func printf(fmt: i8*);
  func exit(code: i32);
  func free(ptr: i8*);
  //func malloc(size: i64): i8*;
  func memcpy(dest: i8*, src: i8*, cnt: i64);
  func fopen(name: i8*, mode: i8*): FILE*;
  func fdopen(fd: i32, mode: i8*): FILE*;
  func open(name: i8*, flags: i32, mode: i32): i32;
  func fclose(file: FILE*): i32;
  //func fflush(file: FILE*): i32;
  func fwrite(buf: i8*, size: i32, count: i32, target: FILE*): i32;
  func fread(buf: i8*, size: i32, count: i32, target: FILE*): i32;
  func fseek(file: FILE*, offset: i64, origin: i32): i32;
  func ftell(file: FILE*): i64;
  func remove(name: i8*): i32;
  func rmdir(path: i8*): i32; /* return 0=ok,1=err */
  func rename(old_name: i8*, new_name: i8*): i32;
  func opendir(dir: i8*): DIR*;
  func readdir(dp: DIR*): dirent*;
  func closedir(dp: DIR*): i32;
  func mkdir(path: i8*, mode: i32): i32;
  func realpath(path: i8*, resolved: i8*): i8*;
  func system(cmd: i8*): i32;
  func putchar(chr: i32): i32;

  func stat(path: i8*, st: stat*): i32;
  func getenv(name: i8*): i8*;
  func setenv(name: i8*, value: i8*, overwrite: i32): i32;
  func unsetenv(name: i8*): i32;

  func atof(ptr: i8*): f64;
  //func sprintf(str: i8*, format: i8*, ...): i32;
}

type dev_t = i64;
type mode_t = i64;
type nlink_t = i64;
type uid_t = i32;
type gid_t = i32;
type dev_t = i64;
type off_t = i64;
type blksize_t = i64;
type blkcnt_t = i64;
type time_t = i64;

#derive(Debug)
struct timespec{
  tv_sec: time_t;
  tv_nsec: time_t;
}

#derive(Debug)
struct stat{
  st_dev: dev_t;      /* ID of device containing file */
  st_ino: ino_t;      /* Inode number */
  st_mode: mode_t;     /* File type and mode */
  st_nlink: nlink_t;    /* Number of hard links */
  st_uid: uid_t;      /* User ID of owner */
  st_gid: gid_t;      /* Group ID of owner */
  st_rdev: dev_t;     /* Device ID (if special file) */
  st_size: off_t;     /* Total size, in bytes */
  st_blksize: blksize_t;  /* Block size for filesystem I/O */
  st_blocks: blkcnt_t;  /* Number of 512 B blocks allocated */
  st_atim: timespec;
  st_mtim: timespec;
  st_ctim: timespec;
  st_atime: time_t;
  st_mtime: time_t;
  st_ctime: time_t;
}