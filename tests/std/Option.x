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

/*impl<T> Clone for Option<T*>{
  func clone(self): Option<T*>{
    if(self.is_none()) return Option<T*>::new();
    return Option<T*>::new(self.get().clone());
  }
}*/
impl<T> Clone for Option<T>{
  func clone(self): Option<T>{
    if(self.is_none()) return Option<T>::new();
    return Option<T>::new(self.get().clone());
  }
}

func drop2<T>(a: T**){

}
func drop2<T>(a: T*){
  Drop::drop(a);
}

impl<T> Drop for Option<T>{
  func drop(*self){
    //if(std::is_ptr<T>()) return;
    if let Option<T>::Some(val)=(self){
      //print("%s::drop\n", std::parent_name());
      Drop::drop(val);
    }
  }
}
