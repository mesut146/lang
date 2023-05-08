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

  func unwrap(self): T{
    if let Some(val) = (self){
      return val;
    }
    panic("unwrap on None");
  }

  func is_some(self): bool{
    return !self.is_none();
  }

  func is_none(self): bool{
    if let None = (self){
      return true;
    }
    return false;
  }
  
  func set(self, val: T){
    //todo
  }

  func dump(self){
    if(self.is_some()){
      print("Option::Some{%d}", self.unwrap());
    }else{
      print("Option::None");
    }
  }
}

