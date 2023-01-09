class A{
  val: int;

  /*static func new0(a: int): A*{
    return new A{val: a};
  }*/
  
  func set(a: int){
    val = a;
  }

  func get(): int{
    return val;
  }
}