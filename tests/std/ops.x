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

impl Clone for i32{
  func clone(self): i32{
    return *self;
  }
}

impl Clone for i64{
  func clone(self): i64{
    return *self;
  }
}

trait Debug{
  func debug(self, f: Fmt*);
}

struct Fmt{
  buf: String;
}

impl Drop for Fmt{
  func drop(self){
    self.buf.drop();
  }
}

impl Debug for [i32]{
  func debug(self, f: Fmt*){
    f.print("[");
    for(let i = 0;i < self.len();++i){
      if(i > 0) print(", ");
      Debug::debug(&i, f);
      f.print("=");
      Debug::debug(&self[i], f);
    }
    f.print("]\n");
  }
}

impl Fmt{
  func new(): Fmt{
    return Fmt{String::new()};
  }
  func print(self, c: i8){
    self.buf.append(c);
  }
  func print(self, s: str){
    self.buf.append(s); 
  }
  func print(self, s: String*){
    self.buf.append(s); 
  }
  
  func str<T>(node: T*): String{
    let f = Fmt::new();
    Debug::debug(node, &f);
    return f.buf.clone();
  }
  func str2<T>(node: T): String{
    let f = Fmt::new();
    Debug::debug(&node, &f);
    return f.buf;
  }

  func format(s: str, args: List<str>*): String{
    let res = String::new();
    let i = 0;
    let arg_idx = 0;
    while(i < s.len()){
      let j = s.indexOf("{}", i);
      if(j == -1){
        res.append(s.substr(i));
        break;
      }
      res.append(s.substr(i, j));
      res.append(args.get(arg_idx));
      i = j + 2;
      ++arg_idx;
    }
    return res;
  }
  func format(s: str, a1: str): String{
    let args = List<str>::new();
    args.add(a1);
    return Fmt::format(s, &args);
  }
  func format(s: str, a1: str, a2: str): String{
    let args = List<str>::new();
    args.add(a1);
    args.add(a2);
    return Fmt::format(s, &args);
  }
  func format(s: str, a1: str, a2: str, a3: str): String{
    let args = List<str>::new();
    args.add(a1);
    args.add(a2);
    args.add(a3);
    return Fmt::format(s, &args);
  }
  func format(s: str, a1: str, a2: str, a3: str, a4: str): String{
    let args = List<str>::new();
    args.add(a1);
    args.add(a2);
    args.add(a3);
    args.add(a4);
    return Fmt::format(s, &args);
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

impl Debug for u8{
  func debug(self, f: Fmt*){
    f.print(*self);
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
  func drop(self);
}

impl Drop for i32{
  func drop(self){
    
  }
}
impl Drop for i64{
  func drop(self){
    
  }
}
impl Drop for str{
  func drop(self){
    
  }
}