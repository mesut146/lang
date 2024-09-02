#derive(Debug)
enum Option<T>{
  None,
  Some(val: T)
}

impl<T> Option<T>{
  func new(val: T): Option<T>{
    return Option<T>::Some{val};  
  }
  func new(): Option<T>{
    return Option<T>::None;  
  }

  func unwrap(*self): T{
    if let Option<T>::Some(val) = (self){
      return val;
    }
    std::no_drop(self);
    panic("unwrap on None");
  }

  func get(self): T*{
    if let Option<T>::Some(val*) = (self){
      return val;
    }
    panic("unwrap on None");
  }

  //read val if no drop type
  func unwrap_ptr(self): T{
    if(std::is_ptr<T>()){
      return *self.get();
    }
    panic("invalid usage");
  }

  func is_some(self): bool{
    return !self.is_none();
  }

  func is_none(self): bool{
    if let Option<T>::None = (self){
      return true;
    }
    return false;
  }
  
  func set(self, val: T){
    //todo return Option{ old val }
    if(self.is_some()){
      let old = ptr::deref(self.get());
      Drop::drop(old);
    }
    std::no_drop(*self);
    *self = Option::new(val);
  }

  func unwrap_or(*self, def: T): T{
    if(self.is_none()){
      std::no_drop(self);
      return def;
    }
    def.drop();
    return self.unwrap();
  }

  //clears value, sets this to None
  func reset(self){
    if(self.is_some()){
      let old = ptr::deref(self.get());
      Drop::drop(old);
    }
    std::no_drop(*self);
    *self = Option<T>::new();
  }

  func dump(self){
    if(self.is_some()){
      print("Option::Some{%d}", self.unwrap());
    }else{
      print("Option::None");
    }
  }
}

impl<T> Clone for Option<T>{
  func clone(self): Option<T>{
    if(self.is_none()) return Option<T>::new();
    return Option<T>::new(self.get().clone());
  }
}

impl<T> Drop for Option<T>{
  func drop(*self){
    //if(std::is_ptr<T>()) return;
    if let Option<T>::Some(val)=(self){
      //print("%s::drop\n", std::parent_name());
      Drop::drop(val);
      return;
    }
    std::no_drop(self);
  }
}
