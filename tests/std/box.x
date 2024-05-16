import std/libc

#drop
struct Box<T>{
    val: T*;
}

impl<T> Box<T>{
    func new(val: T): Box<T>{
        let ptr = malloc<T>(1);
        if((ptr as u64) == 0){
          panic("box alloc failed");
        }
        //*ptr = val;
        ptr::copy(ptr, 0, val);
        std::no_drop(val);
        return Box<T>{val: ptr};
    }

    func get(self): T*{
        return self.val;
    }

    func unwrap(self): T{
        //return *self.val;
        return ptr::deref(self.val);
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
  func drop(*self){
    Drop::drop(self.unwrap());
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
  func is_none(self): bool{
    return self.val.is_none();
  }
  func get(self): T*{
    return self.val.get().get();
  }
  func unwrap(*self): T{
    return self.val.unwrap().unwrap();
  }
}

impl<T> Clone for Ptr<T>{
  func clone(self): Ptr<T>{
    return Ptr<T>{Clone::clone(&self.val)};
  }
}