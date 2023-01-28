enum Optional<T>{
  None,
  Some(val: T);
}

impl Optional<T>{
  func unwrap(self): T{
    if let Optional<T>::Some(val) = (self){
      return val;
    }
    panic("unwrap on None");
  }

  func isSome(self): bool{
    return !self.isNone();
  }

  func isNone(self): bool{
    if let Optional<T>::None = (self){
      return true;
    }
    return false;
  }
}

func optionalTest(){
  let o1 = Optional<i32>::None;
  assert o1.isNone();
  //o1.unwrap(); //panics

  let o2 = Optional<i32>::Some{5};
  assert o2.isSome();
  assert o2.unwrap() == 5;

  print("optionalTest done\n");
}

