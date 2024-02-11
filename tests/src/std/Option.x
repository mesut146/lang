#derive(Debug)
enum Option<T>{
  None,
  Some(val: T)
}

/*match self{
  Some(val) => return val;
  None => panic("unwrap on None");
}*/

impl<T> Option<T>{
  func new(val: T): Option<T>{
    return Option<T>::Some{val};  
  }
  func new(): Option<T>{
    return Option<T>::None;  
  }

  func unwrap(self): T{
    if let Option<T>::Some(val) = (self){
      return val;
    }
    panic("unwrap on None");
  }

  func get(self): T*{
    if let Option<T>::Some(val*) = (self){
      return val;
    }
    panic("unwrap on None");
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
    //todo
    *self = Option::new(val);
  }

  func dump(self){
    if(self.is_some()){
      print("Option::Some{%d}", self.unwrap());
    }else{
      print("Option::None");
    }
  }
}


impl<T> Drop for Option<T>{
  func drop(self){
    if(std::is_ptr<T>()) return;
    if let Option<T>::Some(val*)=(self){
      val.drop();
    }
  }
}
