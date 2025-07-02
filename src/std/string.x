//import std/List
//import std/str
import std/libc

struct String{
    arr: List<u8>;
}

impl String{
    func dump(self){
      print("String{{len: {}, \"", self.len());
      self.print();
      print("\"}\n");
    }

    func print(self){
      printf("%.*s", self.len(), self.ptr() as i8*);
    }
    func println(self){
      printf("%.*s\n", self.len(), self.ptr() as i8*);
    }

    func new(): String{
        return String{arr: List<u8>::new()};
    }
    
    func new(cap: i64): String{
      return String{List<u8>::new(cap)};
    }

    func new(s: str): String{
      let res = String::new(s.len());
      res.append(s);
      res.str().check_all();
      return res;
    }
    
    func new(arr: List<u8>*): String{
      return String::new(arr.slice());
    }

    func new(arr: List<u8>): String{
      return String{arr: arr};
    }
    
    func new(arr: List<i8>*): String{
      return String::new(arr.slice());
    }
    
    func new(arr: [i8]): String{
      let ptr = arr.ptr() as u8*;
      let len = arr.len();
      return String::new(ptr[0..len]);
    }

    func new(arr: [u8]): String{
     let ptr = arr.ptr();
     let len = arr.len();
     let s = String::new(len);
     for(let i = 0;i < len;++i){
       s.append(arr[i]);
     }
     s.str().check_all();
     return s;
    }      

    func len(self): i64{
        return self.arr.len();
    }

    func empty(self): bool{
      return self.len() == 0;
    }
    
    func get(self, i: i64): i8{
         return *self.arr.get(i);
    }

    func str(self): str{
        return str{self.slice()};
    }

    func slice(self): [u8]{
      return self.arr.slice(0, self.len());
    }

    func ptr(self): i8*{
      return self.arr.ptr() as i8*;
    }

    func append(self, s: str): String*{
        for(let i = 0;i < s.len();++i){
            self.append(s.get(i));
        }
        return self;
    }
    
    func append(self, s: String*): String*{
        for(let i = 0;i < s.len();++i){
            self.append(s.get(i));
        }
        return self;
    }
    func append(self, s: String): String*{
      self.append(&s);
      s.drop();
      return self;
    }

    func append(self, chr: i8): String*{
        self.arr.add(chr as u8);
        return self;
    }

    func append(self, chr: u8): String*{
      self.arr.add(chr);
      return self;
    }    
    
    func set(self, pos: i32, c: u8){
      self.arr.set(pos, c);
    }
    
    func replace(self, s1: str, s2: str): String{
      return self.str().replace(s1, s2);
    }
    
    func substr(self, start: i64): str{
      return self.substr(start, self.len() as i32);
    }

    func substr(self, start: i64, end: i64): str{
      return self.str().substr(start, end);
    }
    
    func split(self, sep: str): List<str>{
      return self.str().split(sep);
    }
    
    func eq(self, s: str): bool{
      return self.str().eq(s);
    }

    func cstr(*self): CStr{
      return CStr::new(self);
    }
}

impl Clone for String{
  func clone(self): String{
    return String{self.arr.clone()};
  }
}

impl Debug for String{
  func debug(self, f: Fmt*){
    self.str().debug(f);
    //f.print(self.str());
  }
}
impl Display for String{
  func fmt(self, f: Fmt*){
    self.str().debug(f);
    //f.print(self.str());
  }
}

impl Eq for String{
  func eq(self, rhs: String*): bool{
    return self.str().eq(rhs.str());
  }
}

impl Drop for String{
  func drop(*self){
    //print("String::drop ");
    //self.dump();
    Drop::drop(self.arr);
  }
}

impl Compare for String{
  //compare alphabeticly
  func compare(self, other: String*): i32{
    let os = other.str();
    return self.str().compare(&os);
  }
}


enum CStr{
  Str(val: String),
  Ptr(ptr: i8*)
}

impl CStr{
  func new(s: String): CStr{
    if(s.empty()){
      s.append(0u8);
      --s.arr.count;
    }
    else{
      let last = *s.arr.last();
      if(last != 0){
        s.append(0u8);
      }
      --s.arr.count;
    }
    return CStr::Str{val: s};
  }
  func new(arr: [u8]): CStr{
    let s = String::new(arr);
    return CStr::new(s);
  }
  func new(arr: [i8]): CStr{
    let s = String::new(arr);
    return CStr::new(s);
  }
  func new(s: str): CStr{
    return CStr::new(s.str());
  }
  func new(ptr: i8*): CStr{
    return CStr::Ptr{ptr};
  }
  func ptr(self): i8*{
    match self{
      CStr::Str(val) => return val.ptr(),
      CStr::Ptr(ptr) => return *ptr,
    }
  }
  func str(self): str{
    match self{
      CStr::Str(val) => return val.str(),
      CStr::Ptr(ptr) => return str::from_raw(*ptr),
    }
  }
  func get_heap(self): String{
    match self{
      CStr::Str(val) => return val.clone(),
      CStr::Ptr(ptr) => return str::from_raw(*ptr).owned(),
    }
  }
  func len(self): i64{
    match self{
      CStr::Str(val) => return val.len(),
      CStr::Ptr(ptr) => return str::from_raw(*ptr).len(),
    }
  }
}

impl Debug for CStr{
  func debug(self, f: Fmt*){
    match self{
      CStr::Str(val) => f.print(val),
      CStr::Ptr(ptr) => f.print(str::from_raw(*ptr)),
    }
  }
}
impl Display for CStr{
  func fmt(self, f: Fmt*){
      Debug::debug(self, f);
  }
}

impl Drop for CStr{
  func drop(*self){
     match self{
      CStr::Str(val) => Drop::drop(val),
      CStr::Ptr(ptr) => free(ptr),
    }
  }
}