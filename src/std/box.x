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

    func unwrap(*self): T{
      let res = ptr::deref(self.val);
      std::no_drop(self);
      return res;
    }

    func set(self, e: T): T{
      let old = ptr::deref(self.val);
      ptr::copy(self.val, 0, e);
      return old;
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
    let ptr = self.val as i8*;
    Drop::drop(self.unwrap());
    free(ptr);
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
  func unwrap_box(*self): Box<T>{
    return self.val.unwrap();
  }
  func set(self, e: T): Option<T>{
    if(self.is_some()){
      return Option::new(self.val.get().set(e));
    }
    self.val = Option::new(Box::new(e));
    return Option<T>::new();
  }
}

impl<T> Clone for Ptr<T>{
  func clone(self): Ptr<T>{
    return Ptr<T>{Clone::clone(&self.val)};
  }
}

//c ptr
struct RawPtr<T>{
  ptr: T*;
}

impl<T> RawPtr<T>{
  func new(ptr: T*): RawPtr<T>{
    return RawPtr<T>{ptr: ptr};
  }
  func get(self): T*{
    return self.ptr;
  }
}

impl<T> Drop for RawPtr<T>{
  func drop(*self){
    let ptr = self.ptr as i8*;
    free(ptr);
  }
}