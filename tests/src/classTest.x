class Point{
  x: int;
  y: int;

  static func new(a: int, b: int): Point*{
    return new Point{x: a, y: b};
  }
  
  func set(val: int, i: int){
    if(i==0) x = val;
    else y = val;
  }

  func getX(): int{
    return x;
  }
  func getY(): int{
    return y;
  }
}

func classTest2(): int{
  return 123;
}