class Point{
  x: i32;
  y: i32;
}

impl Point{
  func new(a: i32, b: i32): Point*{
    return new Point{x: a, y: b};
  }

  func getX(self): i32{
    return self.x;
  }
  func getY(self): i32{
    return self.y;
  }
}

func classTest2(): i32{
  return 123;
}