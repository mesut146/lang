enum Optional<T>{
  None,
  Some(val: T);

  func unwrap(): T{
    if let Some(val) = (this){
      return val;
    }
    panic(err);
  }

  func isSome(): bool{
    return !isNone();
  }

  func isNone(): bool{
    if let None = (this){
      return true;
    }
    return false;
  }
}

