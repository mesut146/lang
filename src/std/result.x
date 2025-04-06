enum Result<R, E>{
  Ok(val: R),
  Err(e: E)
}

impl<R, E> Result<R, E>{
  func ok(val: R): Result<R, E>{
    return Result<R, E>::Ok{val};
  }

  func err(val: E): Result<R, E>{
    return Result<R, E>::Err{val};
  }

  func is_ok(self): bool{
    return self is Result<R, E>::Ok;
  }

  func is_err(self): bool{
    return self is Result<R, E>::Err;
  }

  func unwrap(*self): R{
    if let Result<R, E>::Ok(val) = self{
      return val;
    }
    panic("unwrap on empty Result");
  }

  func get(self): R*{
    if let Result<R, E>::Ok(val*) = (self){
      return val;
    }
    panic("unwrap on empty Result");
  }

  func unwrap_err(*self): E{
    if let Result<R, E>::Err(val) = (self){
      return val;
    }
    panic("unwrap on empty Result");
  }
}