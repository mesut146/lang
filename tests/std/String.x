//import std/List
//import std/str
import std/libc

struct String{
    arr: List<u8>;
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
    
    func get(self, i: i64): i8{
         return self.arr.get(i);
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

    func append(self, s: str){
        for(let i = 0;i < s.len();++i){
            self.append(s.get(i));
        }
    }
    
    func append(self, s: String*){
        for(let i = 0;i < s.len();++i){
            self.append(s.get(i));
        }
    }

    func append(self, chr: i8){
        self.arr.add(chr as u8);
    }

    func append(self, chr: u8){
      self.arr.add(chr);
    }    
    
    func set(self, pos: i32, c: u8){
      self.arr.set(pos, c);
    }
    
    func find(self, s: str): Option<i32>{
      return self.find(s, 0);
    }
    
    func find(self, s: str, start: i32): Option<i32>{
      let i = self.str().indexOf(s, start);
      if(i==-1){ 
       return Option<i32>::None; 
      }
      return Option::new(i);
    }
    
    func replace(self, s1: str, s2: str): String{
      let res = String::new();
      let last = 0;
      //"abcdbce" "bc" "x"
      //"axdxe"
      while(true){
        let i = self.find(s1, last);
        if(i.is_some()){
          res.append(self.str().substr(last, i.unwrap()));
          res.append(s2);
          last = i.unwrap() + s1.len();
        }else{
          res.append(self.str().substr(last));
          break;
        }
      }
      return res;
    }
    
    func substr(self, start: i32): str{
      return self.substr(start, self.len() as i32);
    }

    func substr(self, start: i32, end: i32): str{
      return self.str().substr(start, end);
    }
    
    func split(self, sep: str): List<String>{
      let arr = List<String>::new();
      let last = 0;
      while(true){
        let i = self.str().indexOf(sep, last);
        if(i == -1){
          arr.add(self.substr(last).str());
          break;
        }else{
          arr.add(self.substr(last, i).str());
          //print("s = %s\n", arr.last().str().cstr());
          last = i + sep.len();
        }
      }
      return arr;
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
    f.print(self.str());
  }
}

impl Eq for String{
  func eq(self, rhs: String*): bool{
    return self.str().eq(rhs.str());
  }
}

impl Debug for i32{
  func debug(self, f: Fmt*){
    f.print(self.str().str());
  }
  
  func str(self): String{
    let x = *self;
    let len = self.str_size();
    let list = List<u8>::new(len + 1);
    list.set(len, 0u8);//null terminate
    list.count = len;
    for(let i = len - 1;i >= 0;--i){
      let c = x % 10;
      list.set(i, (c + ('0' as i32)) as u8);
      x = x / 10;
    }
    return String{list};
  }
  
  func str_size(self): i32{
    if(*self == 0) return 1;
    let x = *self;
    let res = 0;
    while(x > 0){
      x /= 10;
      res+=1;
    }
    return res;
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
}
impl i64{
  func print(x: i64): String{
    return x.str();
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
    let x = 0_i64;
    let pos = 2;
    while(pos<s.len()){
      let ch = s.get(pos) as i32;
      let y = 0;
      if(ch>='0'&&ch<='9') y = ch - ('0' as i32);
      else if(ch>='a'&&ch<='z') y=ch-('a' as i32)+10;
      else y = ch-'A'+10;
      x = 16*x+y;
      ++pos;
    }
    return x;
  }
  func str(self): String{
    let x = *self;
    let len = self.str_size();
    let list = List<u8>::new(len + 1);
    list.set(len, 0u8);//null terminate
    list.count = len;
    for(let i = len - 1;i >= 0;--i){
      let c = x % 10;
      list.set(i, (c + ('0' as i32)) as u8);
      x = x / 10;
    }
    return String{list};
  }
  
  func str_size(self): i32{
    if(*self == 0) return 1;
    let x = *self;
    let res = 0;
    while(x > 0){
      x /= 10;
      res += 1;
    }
    return res;
  }
}


impl Drop for String{
  func drop(*self){
    //print("String::drop ");
    //self.dump();
    Drop::drop(self.arr);
  }
}


enum CStr{
  Lit(val: str),
  Heap(val: String)
}

impl CStr{
  func new(s: str): CStr{
    return CStr::Lit{s};
  }
  func new(s: String): CStr{
    if(s.len() > 0 && s.get((s.len() - 1) as i32) != 0){
      s.append(0u8);
    }
    //--res.count;
    return CStr::Heap{s};
  }
  func new(arr: [u8]): CStr{
    let s = String::new(arr);
    return CStr::Heap{s};
  }
  func new(arr: [i8]): CStr{
    let s = String::new(arr);
    return CStr::Heap{s};
  }
  func from_slice(s: str): CStr{
    return CStr::Heap{s.str()};
  }
  func ptr(self): i8*{
    if let CStr::Lit(v*)=(self){
      return v.ptr() as i8*;
    }else if let CStr::Heap(v*)=(self){
      return v.ptr();
    }
    panic("CStr::ptr");
  }
  func get(self): str{
    if let CStr::Lit(v)=(self){
      return v;
    }else if let CStr::Heap(v*)=(self){
      return v.str();
    }
    panic("CStr::get");
  }
  func get_heap(self): String{
    return self.get().str();
  }
}

impl Drop for CStr{
  func drop(*self){
    //print("CStr::drop %s\n", self.ptr());
    if let CStr::Heap(v)=(self){
      Drop::drop(v);
    }
  }
}