import std/libc

#drop
struct Box<T>{
    val: T*;
}

impl<T> Box<T>{
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

impl<T> Debug for Box<T>{
  func debug(self, f: Fmt*){
    f.print("Box{");
    Debug::debug(self.val, f);
    f.print("}");
  }
}

impl<T> Clone for Box<T>{
  func clone(self): Box<T>{
    return Box<T>::new(Clone::clone(self.val));
  }
}

impl<T> Drop for Box<T>{
  func drop(self){
    print("drop box\n");
    free(self.val as i8*);
  }
}

struct Ptr<T>{
  val: Option<Box<T>>;
}

impl<T> Ptr<T>{
  func new(val: T): Ptr<T>{
    return Ptr<T>{val: Option::new(Box::new(val))};
  }
  func new(): Ptr<T>{
    return Ptr<T>{val: Option<Box<T>>::None};
  }
  func has(self): bool{
    return self.val.is_some();
  } 
  func is_some(self): bool{
    return self.val.is_some();
  }
  func get(self): T*{
    return self.val.get().get();
  }
  func unwrap(self): T{
    return self.val.unwrap().unwrap();
  }
}

impl<T> Drop for Ptr<T>{
  func drop(self){
    print("drop Ptr<T>\n");
    self.val.drop();
  }
}