import std/str

struct c_void;
struct cFILE;
struct cDIR;

//type char = i8
//type int i32
type size_t = i64;
type ino_t = u64;
type off_t = u64;
type pthread_t = i64;
type pthread_attr_t = c_void;
type pthread_mutexattr_t = c_void;
type suseconds_t = i32;

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

type pid_t = i32;

const O_RDONLY: i32 = 0;
const O_WRONLY: i32 = 1;
const O_RDWR: i32 = 2;

struct dirent {
    d_ino: ino_t;      /* inode number */
    d_off: off_t;      /* offset to the next dirent */
    d_reclen: u16 ;    /* length of this record */
    d_type: u8;        /* type of file; not supported by all file system types */
    d_name: [u8; 256]; /* filename */
}

struct pthread_mutex_t{
  data: [i8; 40];
}

impl dirent{
  func len(self): i32{
    for(let i = 0;i < self.d_name.len();++i){
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
  panic("no eof sl_len={}", arr.len());
}
func strlen(arr: i8*, max: i32): i32{
  for(let i = 0;i < max;++i){
    let chr = *ptr::get!(arr, i);
    if(chr == 0) return i;
  }
  panic("no eof max={}", max);
}
func strlen(ptr: i8*): i32{
  return strlen(ptr, 100000);
}

func is_null<T>(ptr: T*): bool{
  return ptr as u64 == 0;
}

func SEEK_END(): i32 { return 2; }
func SEEK_SET(): i32 { return 0; }
//func SEEK_CUR(): i32 { return 0; }

extern{
  //static stdout: cFILE*;
  
  
  //func printf(fmt: i8*, ...);
  func exit(code: i32);
  func free(ptr: i8*);
  //func malloc(size: i64): i8*;
  func memcpy(dest: i8*, src: i8*, cnt: i64);
  func fopen(name: i8*, mode: i8*): cFILE*;
  func fdopen(fd: i32, mode: i8*): cFILE*;
  func open(name: i8*, flags: i32, mode: i32): i32;
  func fclose(file: cFILE*): i32;
  //func fflush(file: cFILE*): i32;
  func fwrite(buf: i8*, size_of_elem: i32, count: i32, target: cFILE*): i32;
  func fread(buf: i8*, size: i32, count: i32, target: cFILE*): i32;
  func fgets(s: i8*, size: i32, file: cFILE*): i8*;
  func fseek(file: cFILE*, offset: i64, origin: i32): i32;
  func ftell(file: cFILE*): i64;
  func remove(name: i8*): i32;
  func rmdir(path: i8*): i32; /* return 0=ok,1=err */
  func rename(old_name: i8*, new_name: i8*): i32;
  func opendir(dir: i8*): cDIR*;
  func readdir(dp: cDIR*): dirent*;
  func closedir(dp: cDIR*): i32;
  func mkdir(path: i8*, mode: i32): i32;
  func realpath(path: i8*, resolved: i8*): i8*;
  func getcwd(buf: i8*, size: size_t): i8*;
  func system(cmd: i8*): i32;
  func putchar(chr: i32): i32;

  func stat(path: i8*, st: stat*): i32;
  func fchmod(fildes: i32, mode: mode_t): i32;
  func getenv(name: i8*): i8*;
  func setenv(name: i8*, value: i8*, overwrite: i32): i32;
  func unsetenv(name: i8*): i32;

  func atof(ptr: i8*): f64;
  //func sprintf(str: i8*, format: i8*, ...): i32;
  //func pthread_create(th: pthread_t*, attr: pthread_attr_t*, fp: func() => void, arg: c_void*): i32;
  func pthread_create(th: i64*, attr: c_void*, fp: func(c_void*) => void, arg: c_void*): i32;
  //func pthread_join(th: pthread_t, value_ptr: c_void**): i32;
  func pthread_join(th: i64, value_ptr: c_void**): i32;
  func sleep(sec: i32): i32;
  func nanosleep(req: timespec*, rem: timespec*): i32;
  func pthread_mutex_init(mutex: pthread_mutex_t*, attr: pthread_mutexattr_t*): i32;
  func pthread_mutex_destroy(mutex: pthread_mutex_t*): i32;
  func pthread_mutex_lock(mutex: pthread_mutex_t*): i32;
  func pthread_mutex_unlock(mutex: pthread_mutex_t*): i32;
  func strerror(err: i32): i8*;
  
  func popen(cmd: i8*, mode: i8*): cFILE*;
  func pclose(fp: cFILE*): i32;
  func fork(): i32; //pid_t;
  
  func gettimeofday(tv: timeval*, timezone: i8*): i32;

  func strcmp(s1: i8*, s2: i8*): i32;
}

/*struct time{
    tv: timeval;
}*/

func gettime(): timeval{
  let tv: timeval = timeval{0, 0};
  gettimeofday(&tv, ptr::null<i8>());
  return tv;
}

func msleep(ms: i64){
  let tm = timespec{ms/1000, ms%1000};
  nanosleep(&tm, ptr::null<timespec>());
}

func make_pthread_mutex_t(): pthread_mutex_t{
  let m: pthread_mutex_t = pthread_mutex_t{data: [0i8; 40]};
  return m;
}

#derive(Debug)
struct timespec{
  tv_sec: time_t;
  tv_nsec: time_t;
}
impl timespec{
  func as_sec(self): i64{
    return self.tv_sec + self.tv_nsec / 1000000000;
  }
}

#derive(Debug)
struct timeval {
  tv_sec: time_t;     /* seconds */
  tv_usec: suseconds_t;    /* microseconds */
}
impl timeval{
  func as_ms(self): i64{
    return self.tv_sec * 1000 + self.tv_usec / 1000;
  }
  func as_sec(self): i64{
    return self.as_ms() / 1000;
  }
  func sub(self, begin: timeval*): timeval{
    return timeval{
      tv_sec: self.tv_sec - begin.tv_sec,
      tv_usec: self.tv_usec - begin.tv_usec
    };
  }
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
  //st_atime: time_t;
  //st_mtime: time_t;
  //st_ctime: time_t;
}