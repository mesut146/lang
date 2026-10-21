//import std/String
//import std/List
import std/libc

struct str{
  buf: [u8];
}

/*struct str{
  ptr: u8*;
  len: i64;
}*/

impl str{
  func new(buf: [u8]): str{
    let res = str{buf: buf};
    //res.check_all();
    return res;
  }
  func new(buf: [i8]): str{
    let ptr2 = buf.ptr() as u8*;
    let buf2 = ptr2[0..buf.len()];
    let res = str{buf: buf2};
    //res.check_all();
    return res;
  }
  func from_raw(ptr: i8*): str{
    if(is_null(ptr)){
      panic("ptr is null");
    }
    let len = strlen(ptr) as i32;
    return str::new(ptr[0..len]);
  }

    func print(self){
      printf("%.*s", self.len(), self.cptr());
    }
    func println(self){
      printf("%.*s\n", self.len(), self.cptr());
    }
    
    func ptr(self): u8*{
       return &self.buf[0];
    }

    func cptr(self): i8*{
      return &self.buf[0] as i8*;
    }

    func slice(self): [u8]{
      return self.buf;
    }

    func len(self): i32{
      return self.buf.len() as i32;
    }

    func empty(self): bool{
      return self.len() == 0;
    }

    func get(self, i: i32): u8{
      return self.buf[i];
    }

    func starts_with(self, s: str): bool{
      return self.starts_with(s, 0);
    }

    func starts_with(self, s: str, pos: i32): bool{
      return self.indexOf(s, pos) == pos;
    }
    
    func ends_with(self, s: str): bool{
      if(s.len() > self.len()) return false;
      let pos = self.len() - s.len();
      return self.indexOf(s, pos) == pos;
    }

    func indexOf(self, ch: i32, off: i32): i32{
      self.check(off);
      let i = off;
      while (i < self.len()){
        //check first char
        if(self.buf[i] == ch){
          return i;
        }
        ++i;
      }
      return -1;
    }

    func indexOf(self, s: str): i32{
      return self.indexOf(s, 0);
    }

    func indexOf(self, s: str, off: i32): i32{
      if(off < 0) panic("str::indexof off<0, {}", off);
      if((s.len() - off) > self.len()) return -1;
      //if(off == self.len()) return -1;
      let i = off;
      while (i < self.len()){
        //check first char
        if(self.buf[i] != s.buf[0]){
          ++i;
          continue;
        }
        //check rest
        let found = true;
        for(let j = 1;j < s.len() && (i + j) < self.len();++j){
          if(self.buf[i + j] != s.buf[j]){
            found = false;
            break;
          }
        }
        if(found) return i;
        ++i;
      }
      return -1;
    }

    func lastIndexOf(self, s: str): i32{
      //todo optimize
      let i = self.indexOf(s, 0);
      if(i == -1){
        return -1;
      }
      while(true){
        let j = self.indexOf(s, i + 1);
        if(j == -1){
          return i; 
        }
        i = j;
      }
      panic("lastIndexOf");
    }

    func contains(self, s: str): bool{
      return self.indexOf(s, 0) != -1;
    }

    func substr(self, start: i64): str{
      return self.substr(start, self.len());
    }

    func in_index(self, pos: i64): bool{
      return pos >= 0 && pos < self.len();
    }
    
    func check(self, pos: i64){
      if(pos >= 0 && pos < self.len()){
        return;
      }
      panic("index {} out of bounds ({}, {})", pos, 0, self.len());
    }

    //start >= 0 & end < len(), exclusive 
    func substr(self, start: i64, end: i64): str{
      if(start < 0) panic("start index out of bounds {}", start);
      if(end > self.len()) panic("end index out of bounds {} of {}", end, self.len());
      if(start > end) panic("range is invalid {}, {}", start, end);
      return str{self.buf[start..end]};
    }
    
    func eq(self, s: str): bool{
      //cmp answers 0 for two empties as well; the empty() checks were two more
      //calls on the hottest comparison path
      return self.cmp(s) == 0;
    }

    func real_len(self): i32{
      //one len() and one raw last-byte load: this used to be empty()+get()+len()
      //(three out-of-line calls) and cmp() calls it twice
      let n = self.len();
      if(n == 0){
        return 0;
      }
      if(ptr::deref!(ptr::get!(self.ptr(), n - 1)) == 0){
        return n - 1;
      }
      return n;
    }

    func cmp(self, s: str): i32{
      //lengths first (also preserves the trailing-NUL semantics of
      //real_len), then a single memcmp instead of per-byte checked loads.
      let ll = self.real_len();
      let rl = s.real_len();
      if(ll < rl) return -1;
      if(ll > rl) return 1;
      if(ll == 0) return 0;
      let r = memcmp(self.ptr() as i8*, s.ptr() as i8*, ll as u64);
      if(r < 0) return -1;
      if(r > 0) return 1;
      return 0;
    }

    func owned(self): String{
      return String::new(*self);
    }
    
    func str(self): String{
      return String::new(*self);
    }

    func cstr(self): CStr{
      return CStr::new(*self);
    }
    
    func split(self, sep: str): List<str>{
      let arr = List<str>::new();
      let last = 0;
      while(true){
        let i = self.indexOf(sep, last);
        if(i == -1){
          if(last < self.len()){
            arr.add(self.substr(last));
          }
          break;
        }else{
          arr.add(self.substr(last, i));
          last = i + sep.len();
        }
      }
      return arr;
    }
    
    func join(self, arr: List<String>*): String{
      let res = String::new();
      for(let i = 0;i < arr.len();++i){
        let s = arr.get(i);
        res.append(s.str());
        if(i + 1 < arr.len()){
          res.append(*self);
        }
      }
      return res;
    }

    func replace(self, s1: str, s2: str): String{
      let res = String::new();
      let last = 0;
      //"abcdbce" "bc" "x"
      //"axdxe"
      while(true){
        let i = self.indexOf(s1, last);
        if(i != -1){
          if(i > last){
            res.append(self.substr(last, i));
          }
          res.append(s2);
          last = i + s1.len();
        }else{
          if(last < self.len()){
            res.append(self.substr(last));
          }
          break;
        }
      }
      return res;
    }

    func is_ws(ch: i32): bool{
      return ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D;
    }

    func trim(self): str{
      let start = 0;
      let end = self.len() - 1;
      while(start <= end && is_ws(self.get(start))){
        ++start;
      }
      while(end >= start && is_ws(self.get(end))){
        --end;
      }
      return self.substr(start, end + 1);
    }
}

impl Compare for str{
  //compare alphabeticly
  func compare(self, other: str*): i32{
    let len1 = self.len();
    let len2 = other.len();
    let min_len = len1;
    if(len2 < len1){
      min_len = len2;
    }
    for(let i = 0;i < min_len;++i){
      let c1 = self.get(i);
      let c2 = other.get(i);
      if(c1 < c2){
        return -1;
      }
      if(c1 > c2){
        return 1;
      }
    }
    return Compare::compare(&len1, &len2);
  }
}