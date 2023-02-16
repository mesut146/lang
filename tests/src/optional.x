enum Option<T>{
  None,
  Some(val: T);
}

/*match self{
  Some(val) => return val;
  None => panic("unwrap on None");
}*/

impl Option<T>{
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
}

func optionalTest(){
  let o1 = Option<i32>::None;
  assert o1.is_none();
  //o1.unwrap(); //panics

  let o2 = Option<i32>::Some{5};
  assert o2.is_some();
  assert o2.unwrap() == 5;

  print("optionalTest done\n");
}

