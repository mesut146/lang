class Box<T>{
    val: T*;
}

impl Box<T>{
    func new(val: T): Box<T>{
        let ptr = malloc<T>(1);
        *ptr = val;
        return Box<T>{val: ptr};
    }

    func get(self): T*{
        return self.val;
    }

    func unwrap(self): T{
        return *self.val;
    }
}

impl Debug for Box<T>{
  func debug(self, f: Fmt*){
    f.print("Box{");
    Debug::debug(self.val, f);
    f.print("}");
  }
}

