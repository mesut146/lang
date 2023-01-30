class str{
  buf: [i8];
}

impl str{
    func len(self): i32{
      return self.buf.len;
    }

    func new(buf: [i8]): str{
        return str{buf: buf};
    }

    func get(self, i: i32): i8{
      return self.buf[i];
    }

    func starts_with(self, s: str*): bool{
      return self.indexOf(s, 0) == 0;
    }

    func indexOf(self, s: str*, off: i32): i32{
      let i = off;
      while (i < s.len()){
        if(self.buf[i] != s.buf[0]){
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

    func contains(self, s: str*): bool{
      return self.indexOf(s, 0) != -1;
    }
}


func strTest(){
    let helloArr = ['h' as i8, 'e', 'l', 'l', 'o'];
    let helloSlice = helloArr[0..5];
    let s = str::new(helloSlice);
}