//import std/List
//import std/str

class String{
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
        return res;
    }
    
    func new(arr: List<u8>*): String{
        return String::new(arr.slice());
    }
    
    func new(arr: List<i8>): String{
        return String::new(arr.slice());
    }
    
    func new(arr: [i8]): String{
        let ptr = arr.ptr();
        let len = arr.len();
        let s = String::new(len);
        for(let i = 0;i < len;++i){
          s.append(arr[i]);
        }
        return s;
    }

    func new(arr: [u8]): String{
      let s = String::new(arr.len());
      for(let i = 0;i < arr.len();++i){
        s.append(arr[i]);
      }
      return s;
  }      

    func len(self): i64{
        return self.arr.len();
    }
    
    func get(self, i: i64): i8{
         return self.arr.get(i);
    }

    func str(self): str{
        return str{self.arr.slice(0, self.len())};
    }

    func slice(self): [u8]{
      return self.arr.slice(0, self.len());
    }
    
    func cstr(self): u8*{
      if(self.len() == 0 || self.get((self.len() - 1) as i32) != 0){
        let res = self.clone();
        res.append(0u8);
        return res.arr.ptr();
      }
      return self.arr.ptr();
    }

    func append(self, s: str){
        for(let i = 0;i < s.len();++i){
            self.append(s.get(i));
        }
    }
    
    func append(self, s: String){
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
    func eq(self, s: String*): bool{
      return self.str().eq(s.str());
    }
}

impl Clone for String{
  func clone(self): String{
    return String{self.arr.clone()};
  }
}

impl Debug for String{
  func debug(self, f: Fmt*){
    f.print(*self);
  }
}

impl Eq for String{
  func eq(self, rhs: String): bool{
    return self.eq(&rhs);
  }
}

impl Debug for i32{
  func debug(self, f: Fmt*){
    f.print(self.str());
  }
  
  func str(self): String{
    let x = self;
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

impl i32{
  func parse(s: String*): i32{
    let x = i64::parse(s);
    return x as i32;
  }
}
impl i64{
  func parse(s: String*): i64{
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
}
