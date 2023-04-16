import List
import str
import impl

class String{
    arr: List<i8>;
}

impl String{
    func dump(self){
      let i = 0;
      print("String{len: %d, \"", self.len());
      while (i < self.len()){
        print("%c", self.arr.get(i));
        ++i;
      }
      print("\"}\n");
    }

    func new(): String{
        return String{arr: List<i8>::new()};
    }
    
    func new(cap: i64): String{
      return String{List<i8>::new(cap)};
    }

    func new(s: str): String{
        let res = String::new();
        res.append(s);
        return res;
    }
    
    func new(arr: List<i8>*): String{
        return String{*arr};
    }
    

    func len(self): i64{
        return self.arr.len();
    }
    
    func get(self, i: i32): i8{
         return self.arr.get(i);
    }

    func str(self): str{
        return str{self.arr.slice(0, self.len())};
    }
    
    func cstr(self): i8*{
      if(self.get((self.len()-1) as i32)!=0){
        self.append(0i8);
      }
      return self.arr.arr;
    }

    func append(self, s: str){
        for(let i = 0;i < s.len();++i){
            self.arr.add(s.get(i));
        }
    }
    
    func append(self, s: String){
        for(let i = 0;i < s.len();++i){
            self.arr.add(s.get(i));
        }
    }

    func append(self, chr: i8){
        self.arr.add(chr);
    }
    
    func clone(self): Self{
      return String{self.arr.clone()};
    }
    
    func set(self, pos: i32, c: i8){
      self.arr.set(pos, c);
    }
}

class Fmt{
  buf: String;
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
   Debug::debug(t, f);
   return f.buf;
 }
}

trait Debug{
  func debug(self, f: Fmt*);
}

impl Debug for i32{
  func debug(self, f: Fmt*){
    f.print(self.str());
  }
  func str(self): String{
    let x = self;
    let len = self.str_size();
    let list = List<i8>::new(len +1);
    list.count = len;
    list.set(len, 0i8);//null terminate
    for(let i=len-1;i >= 0;--i){
      let c = x % 10;
      list.set(i, (c + '0') as i8);
      x = x / 10;
    }
    return String{list};
  }
  func str_size(self): i32{
    if(self==0) return 1;
    let x = self;
    let res = 0;
    while(x > 0){
      x /= 10;
      res+=1;
    }
    return res;
  }
}