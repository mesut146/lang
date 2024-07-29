enum Result<E, R>{
  Err(e: E),
  Ok(val: R)
}

impl<E, R> Result<E, R>{
  func is_err(self): bool{
    return self is Result<E, R>::Err;
  }
  func unwrap(self): R{
    if let Result<E, R>::Ok(val)= (self){
      return val;
    }
    panic("unwrap on empty Result");
  }
}