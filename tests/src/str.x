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
}


func strTest(){
    let helloArr = ['h' as i8, 'e', 'l', 'l', 'o'];
    let helloSlice = helloArr[0..5];
    let s = str::new(helloSlice);

    lit();

    print("strTest done\n");
}

func lit(){
  let s2 = "hello";
  assert s2.len() == 5;
  assert s2.get(1) == 'e';
  //s2.buf[0] = 'H' as i8; //error
  assert s2.indexOf("ll", 0) == 2;
  print("%s\n", s2);
}