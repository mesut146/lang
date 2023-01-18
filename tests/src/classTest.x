class Point{
  x: int;
  y: int;

  static func new(a: int, b: int): Point*{
    return new Point{x: a, y: b};
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

class A{
 a: long;
 b: [int; 100];
}

func by_val(p: A){
  p.a = 11;
  assert p.a == 11;
}

func passTest(){
  let arr = [0; 100];
  let p = A{a: 10, b: arr};
  by_val(p);
  assert p.a == 10;
  print("passTest done\n");
}