//import std/String
//import std/List
import std/libc

struct str{
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

    func print(self){
      printf("%.*s", self.len(), self.cptr());
    }
    
    func ptr(self): u8*{
       return &self.buf[0];
    }

    func cptr(self): i8*{
      return &self.buf[0] as i8*;
    }

    func len(self): i32{
      return self.buf.len() as i32;
    }

    func new(buf: [u8]): str{
        let res = str{buf: buf};
        res.check_all();
        return res;
    }

    func get(self, i: i32): u8{
      return self.buf[i];
    }

    func check(self, pos: i32){
      if(pos < 0 || pos >= self.len()) panic("str::check %s of idx %d", self.cstr().ptr(), pos);
    }

    func starts_with(self, s: str): bool{
      return self.indexOf(s, 0) == 0;
    }
    
    func ends_with(self, s: str): bool{
      if(s.len() > self.len()) return false;
      let pos = self.len() - s.len();
      return self.indexOf(s, pos) == pos;
    }

    func is_valid(c: i8){
      if(c == 0) return;
      if(c >= '0' && c <= '9') return;
      if(c >= 'a' && c <= 'z') return;
      if(c >= 'A' && c <= 'Z') return;
      let arr = ['"', '\'', '\n','\r','\t', ' ', '{', '}', '(',')','=','*','+','-','/',':',';','!','%',',','.','^','$','&','|','[',']','?','\\','_','<','>','~','#'];
      for(let i = 0;i < arr.len();++i){
        if(arr[i] == c) return;
      }
      print("str::is_valid (%d)='%c'\n", c, c);
      panic("");
    }

    func check_all(self){
      for(let i=0;i<self.len();++i){
        is_valid(self.buf[i]);
      }
    }

    func indexOf(self, s: str, off: i32): i32{
      if(off < 0) panic("indexof off=%d", off);
      //if(off == self.len()) return -1;
      //self.check(off);
      let i = off;
      while (i < self.len()){
        //check first char
        is_valid(self.buf[i]);
        is_valid(s.buf[0]);
        //print("iof %c(%d) %c(%d)\n", self.buf[i], self.buf[i], s.buf[0], s.buf[0]);
        if(self.buf[i] != s.buf[0]){
          ++i;
          continue;
        }
        //check rest
        let found = true;
        for(let j = 1;j < s.len() && (i + j) < self.len();++j){
          is_valid(self.buf[i + j]);
          is_valid(s.buf[j]);
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

    func real_len(self): i32{
      if(self.get(self.len() - 1) == 0){
        return self.len() - 1;
      }
      return self.len();
    }

    func cmp(self, s: str): i32{
      if(self.real_len() < s.real_len()) return -1;
      if(self.real_len() > s.real_len()) return 1;
      for(let i=0;i < self.real_len();++i){
        if(self.get(i) < s.get(i)) return -1;
        if(self.get(i) > s.get(i)) return 1;
      }
      return 0;
    }
    
    func str(self): String{
      return String::new(*self);
    }

    func cstr(self): CStr{
      return CStr::from_slice(*self);
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
          last = i + sep.len();
        }
      }
      return arr;
    }
    
    func join(self, arr: List<String>*): String{
      let res = String::new();
      for(let i=0;i<arr.len();++i){
        let s = arr.get_ptr(i);
        res.append(s.str());
        if(i+1<arr.len()){
          res.append(*self);
        }
      }
      return res;
    }

}
