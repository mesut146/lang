trait Eq{
  func eq(self, x: Self): bool;
}

impl Eq for i32{
  func eq(self, x: i32): bool{
    return self == x;
  }
}

impl Eq for i64{
  func eq(self, x: i64): bool{
    return self == x;
  }
}

trait Clone{
  func clone(self): Self;
}

impl Clone for i32{
  func clone(self): i32{
    return self;
  }
}

impl Clone for i64{
  func clone(self): i64{
    return self;
  }
}

trait Debug{
  func debug(self, f: Fmt*);
}

class Fmt{
  buf: String;
}

impl Debug for [i32]{
  func debug(self, f: Fmt*){
    f.print("[");
    for(let i = 0;i < self.len;++i){
      if(i > 0) print(", ");
      Debug::debug(i, f);
      f.print("=");
      Debug::debug(self[i], f);
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
  func print(self, s: String){
    self.buf.append(s); 
  }
  
 func str<T>(t: T): String{
   let f = Fmt::new();
   Debug::debug(t, &f);
   return f.buf;
 }
}

trait Hash{
  func hash(self): i64;
}

impl Hash for i32{
  func hash(self): i64{
    return self as i64;
  }
}
impl Hash for i64{
  func hash(self): i64{
    return self as i64;
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