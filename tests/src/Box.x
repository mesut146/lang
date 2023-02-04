class Box<T>{
    val: T*;
}

impl Box<T>{
    func new(val: T): Box<T>{
        let ptr = malloc<T>(1);
        *ptr = val;
        return Box{val: ptr};
    }

    func get(self): T*{
        return self.val;
    }

    func unwrap(self): T{
        return *self.val;
    }
}

func boxText(){
  let b = Box<i32>::new(5);
}