import std/libc
import std/result

func dbg(c: bool, id: i32){
  if(c){
    let a = 10;
  }
}
func dbg(s1: String, s2: str, id: i32){
  dbg(s1.eq(s2), id);
  s1.drop();
}

struct Pair<K, V>{
  a: K;
  b: V;
}

impl<K, V> Pair<K, V>{
  func new(a: K, b: V): Pair<K, V>{
    return Pair{a, b};
  }
}

trait Eq{
  func eq(self, x: Self*): bool;
}

impl Eq for i32{
  func eq(self, x: i32*): bool{
    return *self == *x;
  }
}

impl Eq for i64{
  func eq(self, x: i64*): bool{
    return *self == *x;
  }
}

impl Eq for str{
  func eq(self, x: str*): bool{
    return self.eq(*x);
  }
}

trait Clone{
  func clone(self): Self;
}

impl Clone for i8{
  func clone(self): i8{
    return *self;
  }
}
impl Clone for u8{
  func clone(self): u8{
    return *self;
  }
}
impl Clone for i16{
  func clone(self): i16{
    return *self;
  }
}
impl Clone for u16{
  func clone(self): u16{
    return *self;
  }
}
impl Clone for i32{
  func clone(self): i32{
    return *self;
  }
}
impl Clone for u32{
  func clone(self): u32{
    return *self;
  }
}
impl Clone for i64{
  func clone(self): i64{
    return *self;
  }
}
impl Clone for u64{
  func clone(self): u64{
    return *self;
  }
}

trait Debug{
  func debug(self, f: Fmt*);
}
trait Display{
  func fmt(self, f: Fmt*);
}

func to_string<T>(node: T*): String{
    let f = Fmt::new();
    node.fmt(&f);
    return f.unwrap();
}

struct Fmt{
  buf: String;
}
impl Fmt{
  func new(): Fmt{
    return Fmt{String::new()};
  }
  func new(s: String): Fmt{
    return Fmt{s};
  }
  func unwrap(*self): String{
    let res = self.buf;
    std::no_drop(self);
    return res;
  }
  func print(self, c: i8){
    self.buf.append(c);
  }
  func print(self, s: str){
    self.buf.append(s); 
  }
  func print(self, s: String){
    self.buf.append(&s);
    s.drop();
  }
  func print<T>(self, node: T*){
    Debug::debug(node, self);
  }
  
  func str<T>(node: T*): String{
    let f = Fmt::new();
    Debug::debug(node, &f);
    let res = f.buf.clone();
    Drop::drop(f);
    return res;
  }
}

impl Debug for [i32]{
  func debug(self, f: Fmt*){
    f.print("[");
    for(let i = 0;i < self.len();++i){
      if(i > 0) {
        f.print(", ");
      }
      Debug::debug(&i, f);
      f.print("=");
      Debug::debug(&self[i], f);
    }
    f.print("]\n");
  }
}
impl Debug for bool{
  func debug(self, f: Fmt*){
    if(*self){
      f.print("true");
    }else{
      f.print("false");
    }
  }
}
impl Display for bool{
  func fmt(self, f: Fmt*){
      Debug::debug(self, f);
  }
}
impl Debug for str{
  func debug(self, f: Fmt*){
    //f.print("\"");
    f.print(*self);
    //f.print("\"");
  }
}
impl Display for str{
  func fmt(self, f: Fmt*){
      Debug::debug(self, f);
  }
}
impl Debug for i8{
  func debug(self, f: Fmt*){
    f.print(*self);
  }
}
impl Display for i8{
  func fmt(self, f: Fmt*){
    f.print(*self);
  }
}
impl Debug for u8{
  func debug(self, f: Fmt*){
    f.print(*self);
  }
}
impl Display for u8{
  func fmt(self, f: Fmt*){
    f.print(*self);
  }
}
//prims
impl Debug for i32{
  func debug(self, f: Fmt*){
    let str = self.str();
    f.print(&str);
    Drop::drop(str);
  }
}
impl Display for i32{
  func fmt(self, f: Fmt*){
      Debug::debug(self, f);
  }
}
impl Debug for i64{
  func debug(self, f: Fmt*){
    let str = self.str();
    f.print(&str);
    Drop::drop(str);
  }
}
impl Display for i64{
  func fmt(self, f: Fmt*){
      Debug::debug(self, f);
  }
}
impl Debug for f32{
  func debug(self, f: Fmt*){
    let str = self.str();
    f.print(&str);
    Drop::drop(str);
  }
}
impl Display for f32{
  func fmt(self, f: Fmt*){
      Debug::debug(self, f);
  }
}
impl Debug for f64{
  func debug(self, f: Fmt*){
    let str = self.str();
    f.print(&str);
    Drop::drop(str);
  }
}
impl Display for f64{
  func fmt(self, f: Fmt*){
      Debug::debug(self, f);
  }
}
impl Debug for u64{
  func debug(self, f: Fmt*){
    i64::debug(*self as i64, f);
  }
}
impl Display for u64{
  func fmt(self, f: Fmt*){
      Debug::debug(self, f);
  }
}

trait Hash{
  func hash(self): i64;
}

impl Hash for i32{
  func hash(self): i64{
    return *self as i64;
  }
}
impl Hash for i64{
  func hash(self): i64{
    return *self as i64;
  }
}
impl Hash for str{
  func hash(self): i64{
    let x: i64 = 0;
    let m: i64 = 1i64 << 31;
    for(let i = 0;i < self.len();++i){
      x = (x * 31 + self.get(i)) % m;
    }
    //print("hash {}={:?}\n", self, x);
    return x;
  }
}
impl Hash for String{
  func hash(self): i64{
      return self.str().hash();
  }
}

trait Drop{
  func drop(*self);
}

impl Drop for u8{
  func drop(*self){
  }
}
impl Drop for u16{
  func drop(*self){
  }
}
impl Drop for u32{
  func drop(*self){
  }
}
impl Drop for u64{
  func drop(*self){
  }
}
impl Drop for i8{
  func drop(*self){
  }
}
impl Drop for i16{
  func drop(*self){
  }
}
impl Drop for i32{
  func drop(*self){
  }
}
impl Drop for i64{
  func drop(*self){
  }
}
impl Drop for str{
  func drop(*self){
  }
}

impl i32{
  func parse(s: str): Result<i32, String>{
    let res = i64::parse(s);
    if(res.is_ok()){
      return Result<i32, String>::ok(res.unwrap() as i32);
    }else{
      return Result<i32, String>::err(res.unwrap_err());
    }
  }

  func parse_hex(s: str): Result<i32, String>{
      let res = i64::parse_hex(s);
      if(res.is_ok()){
        return Result<i32, String>::ok(res.unwrap() as i32);
      }else{
        return Result<i32, String>::err(res.unwrap_err());
      }
  }

  func print(x: i32): String{
    return x.str();
  }

  func str(self): String{
    return i64::print(*self as i64);
  }
}

impl i64{
  func str(self): String{
    return i64::print(*self);
  }
  func parse(s: str): Result<i64, String>{
    let x: i64 = 0;
    let neg = false;
    let pos = 0;
    if(s.get(0) as u32 == '-'){
      ++pos;
      neg = true;
    }
    if(pos == s.len()){
      return Result<i64, String>::err(format("number is too short {}", s));
    }
    while(pos < s.len()){
      let ch = s.get(pos) as i32;
      if(!(ch >= '0' && ch <= '9')){
        return Result<i64, String>::err(format("invalid digit '{}' at pos {}", ch as u8, pos));
      }
      x = 10 * x + (ch as i64 - ('0' as i64));
      ++pos;
    }
    if(neg){
      return Result<i64, String>::ok(-x);
    }
    return Result<i64, String>::ok(x);
  }
  func parse_hex(s: str): Result<i64, String>{
    let neg = false;
    let len = s.len();
    let pos = 0;
    if(s.get(0) as u32 == '-'){
      ++pos;
      neg = true;
      --len;
    }
    if(s.get(pos) == '0' && s.get(pos + 1) == 'x'){
      pos += 2;
    }
    if(pos >= s.len()){
      return Result<i64, String>::err(format("hex is too short {}", s));
    }
    let x = 0_i64;
    while(pos < s.len()){
      let ch = s.get(pos) as i32;
      let y = 0;
      if(ch >= '0' && ch <= '9'){
        y = ch - ('0' as i32);
      }
      else if(ch >= 'a' && ch <= 'f'){
        y = ch - ('a' as i32) + 10;
      }
      else if(ch >= 'A' && ch <= 'F'){
        y = ch - ('A' as i32) + 10;
      }
      else{
        return Result<i64, String>::err(format("invalid hex char: {}({}) in {}", ch as i8, ch, s));
      }
      x = 16 * x + y;
      ++pos;
    }
    if(neg){
      return Result<i64, String>::ok(-x);
    }
    return Result<i64, String>::ok(x);
  }

  func print(x: i64): String{
    let len = i64::str_size(x, 10);
    let list = List<u8>::new(len);
    list.count = len;
    let start_idx = 0;
    if(x < 0){
      x = -x;
      list.set(0, '-' as u8);
      ++start_idx;
    }
    for(let i = len - 1;i >= start_idx;--i){
      let c = x % 10;
      list.set(i, (c + ('0' as i32)) as u8);
      x = x / 10;
    }
    return String{list};
  }
  
  func str_size(x: i64, base: i32): i32{
    if(x == 0) return 1;
    let res = 0;
    if(x < 0){
      x = -x;
      res += 1;
    }
    while(x > 0){
      x /= base;
      res += 1;
    }
    return res;
  }

  func print_hex(x: i64): String{
    let len = i64::str_size(x, 16) + 2;
    let list = List<u8>::new(len);
    list.count = len;
    let start_idx = 0;
    if(x < 0){
      x = -x;
      list.set(0, '-' as u8);
      ++start_idx;
    }
    list.set(start_idx, '0' as u8);
    ++start_idx;
    list.set(start_idx, 'x' as u8);
    ++start_idx;
    let digits: str = "0123456789abcdef";
    for(let i = len - 1;i >= start_idx;--i){
      let rem = x % 16;
      let c = digits.get(rem as i32);
      list.set(i, c);
      x = x / 16;
    }
    return String{list};
  }
  func debug_hex(x: i64, f: Fmt*){
    let str = i64::print_hex(x);
    f.print(&str);
    Drop::drop(str);
  }
}

impl f32{
  func parse(s: str): f32{
    let x = f64::parse(s);
    return x as f32;
  }
  func print(x: f32): String{
    return x.str();
  }
  func str(self): String{
    return f64::print(*self as f64);
  }
}

impl f64{
  func str(self): String{
    return f64::print(*self);
  }
  func parse(s: str): f64{
    let cs = CStr::new(s);
    let res: f64 = atof(cs.ptr());
    cs.drop();
    return res;
  }

  func print(x: f64): String{
    let buf = [0_i8;100];
    let len = sprintf(buf.ptr(), "%f", x);
    let res = str::new(buf[0..len]).str();
    return res;
  }

}

trait Compare{
  //-1, 0, 1
  func compare(self, other: Self*): i32;
}
impl Compare for i32{
  func compare(self, other: i32*): i32{
    if(*self < *other){
      return -1;
    }
    if(*self > *other){
      return 1;
    }
    return 0;
  }
}

func assign_eq<T>(l: T*, r: T){
  let lval = ptr::deref!(l);
  std::no_drop(*l);
  *l = r;
  lval.drop();
}


func assert_eq(s1: String*, s2: String*){
  if(!s1.eq(s2)){
    panic("assertion failed: {}!= {}", s1, s2);
  }
}
func assert_eq(s1: str, s2: str){
  if(!s1.eq(s2)){
    panic("assertion failed: {}!= {}", s1, s2);
  }
}
func assert_eq(s1: i32, s2: i32){
  if(s1 != s2){
    panic("assertion failed: {}!= {}", s1, s2);
  }
}
func assert_eq(s1: String, s2: String){
  if(!s1.eq(s2.str())){
    panic("assertion failed: {}!= {}", s1, s2);
  }
  s1.drop();
  s2.drop();
}
func assert_eq(s1: String, s2: str){
  if(!s1.eq(s2)){
    panic("assertion failed: {}!= {}", s1, s2);
  }
  s1.drop();
}

func assert2(c: bool, msg: String){
  if(!c){
    panic("{}\n", msg);
  }
  msg.drop();
}