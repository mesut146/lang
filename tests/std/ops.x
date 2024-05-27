import std/libc

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
    return self.buf;
  }
  func print(self, c: i8){
    self.buf.append(c);
  }
  func print(self, s: str){
    self.buf.append(s); 
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

impl Debug for str{
  func debug(self, f: Fmt*){
    f.print(*self);
  }
}

impl Debug for i8{
  func debug(self, f: Fmt*){
    f.print(*self);
  }
}

impl Debug for u8{
  func debug(self, f: Fmt*){
    f.print(*self);
  }
}
impl Debug for u64{
  func debug(self, f: Fmt*){
    i64::debug(*self as i64, f);
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
    for(let i = 0;i < self.len();++i){
      x = x * 31 + self.get(i);
    }
    return x;
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

//prims
impl Debug for i32{
  func debug(self, f: Fmt*){
    let str = self.str();
    f.print(&str);
    Drop::drop(str);
  }
}
impl Debug for i64{
  func debug(self, f: Fmt*){
    let str = self.str();
    f.print(&str);
    Drop::drop(str);
  }
}

impl i32{
  func parse(s: str): i32{
    let x = i64::parse(s);
    return x as i32;
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
  func parse(s: str): i64{
    let x: i64 = 0;
    let neg = false;
    let pos = 0;
    if(s.get(0) as u32 == '-'){
      ++pos;
      neg = true;
    }
    while(pos < s.len()){
      x = 10 * x + (s.get(pos) as i64 - ('0' as i64));
      ++pos;
    }
    if(neg){
      return -x;
    }
    return x;  
  }
  func parse_hex(s: str): i64{
    let neg = false;
    let len = s.len();
    let pos = 0;
    if(s.get(0) as u32 == '-'){
      ++pos;
      neg = true;
      --len;
    }
    if(len <= 2){
      panic("hex is too short {}", s);
    }
    if(s.get(pos) != '0' || s.get(pos + 1) != 'x'){
      panic("invalid hex {}", s);
    }
    let x = 0_i64;
    pos += 2;
    while(pos < s.len()){
      let ch = s.get(pos) as i32;
      let y = 0;
      if(ch >= '0' && ch <= '9') y = ch - ('0' as i32);
      else if(ch >= 'a' && ch <= 'f') y = ch - ('a' as i32) + 10;
      else if(ch >= 'A' && ch <= 'F') y = ch - ('A' as i32) + 10;
      else panic("invalid hex char: {}({}) in {}", ch as i8, ch, s);
      x = 16 * x + y;
      ++pos;
    }
    if(neg){
      return -x;
    }
    return x;
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