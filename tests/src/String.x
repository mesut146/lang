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

    func len(self): i64{
        return self.arr.len();
    }

    func str(self): str{
        return str{self.arr.slice(0, self.len())};
    }

    func append(self, s: str){
        let i = 0;
        while(i < s.len()){
            self.arr.add(s.get(i));
            i += 1;
        }
    }

    func append(self, chr: i8){
        self.arr.add(chr);
    }
}