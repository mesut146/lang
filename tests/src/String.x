import List
import str

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

    func new(s: str): String{
        let res = String::new();
        res.append(s);
        return res;
    }

    func len(self): i64{
        return self.arr.len();
    }

    func str(self): str{
        return str{self.arr.slice(0, self.len())};
    }

    func append(self, s: str){
        for(let i = 0;i < s.len();++i){
            self.arr.add(s.get(i));
        }
    }

    func append(self, chr: i8){
        self.arr.add(chr);
    }
}