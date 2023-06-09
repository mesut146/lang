//import std/String
//import std/List

class str{
  buf: [u8];
}

impl str{
    func dump(self){
      let i = 0;
      print("str{len: %d, \"", self.len());
      while (i < self.len()){
        print("%c", self.buf[i]);
        ++i;
      }
      print("\"}\n");
    }
    
    func ptr(self): u8*{
       return &self.buf[0];
    }

    func len(self): i32{
      return self.buf.len;
    }

    func new(buf: [u8]): str{
        return str{buf: buf};
    }

    func get(self, i: i32): u8{
      return self.buf[i];
    }

    func starts_with(self, s: str): bool{
      return self.indexOf(s, 0) == 0;
    }
    
    func ends_with(self, s: str): bool{
      let pos = self.len() - s.len();
      return self.indexOf(s, pos) == pos;
    }    

    func indexOf(self, s: str, off: i32): i32{
      let i = off;
      while (i < self.len()){
        if(self.buf[i] != s.buf[0]){
          ++i;
          continue;
        }
        //rest
        let j = 1;
        let found = true;
        while(i<s.len()){
          if(self.buf[i + j - 1] != s.buf[j]){
            found = false;
            break;
          }
         }
        if(found) return i;
        ++i;
      }
      return -1;
    }

    func contains(self, s: str): bool{
      return self.indexOf(s, 0) != -1;
    }

    func substr(self, start: i32): str{
      return self.substr(start, self.len());
    }

    func substr(self, start: i32, end: i32): str{
      if(start > self.len()) panic("start index out of bounds %d of %d", start, self.len());
      if(end > self.len()) panic("end index out of bounds %d of %d", end, self.len());
      if(start == end){
        let arr = [0u8];
        return str{arr[0..0]};
      }
      assert start < end;
      return str{self.buf[start..end]};
    }
    
    func eq(self, s: str): bool{
      return self.cmp(s) == 0;
    }

    func cmp(self, s: str): i32{
      if(self.len() < s.len()) return -1;
      if(self.len() > s.len()) return 1;
      for(let i=0;i < self.len();++i){
        if(self.get(i) < s.get(i)) return -1;
        if(self.get(i) > s.get(i)) return 1;
      }
      return 0;
    }
    
    func str(self): String{
      return String::new(*self);
    }
    
    func split(self, sep: str): List<str>{
      let arr = List<str>::new();
      let last = 0;
      while(true){
        let i = self.indexOf(sep, last);
        if(i == -1){
          arr.add(self.substr(last));
          break;
        }else{
          arr.add(self.substr(last, i));
          //print("s = %s\n", arr.last().str().cstr());
          last = i + sep.len();
        }
      }
      return arr;
    }

}
