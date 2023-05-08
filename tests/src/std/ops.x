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
    print("[");
    for(let i = 0;i < self.len;++i){
      if(i > 0) print(", ");
      print("%d=%d", i, self[i]);
    }
    print("]\n");
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