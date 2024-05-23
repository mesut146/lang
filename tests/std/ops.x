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
  // func print(self, s: String*){
  //   self.buf.append(s); 
  // }
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
  /*func str2<T>(node: T): String{
    return Fmt::str(&node);
  }*/
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