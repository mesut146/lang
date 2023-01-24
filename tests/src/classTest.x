class Point{
  x: int;
  y: int;
}

impl Point{
  func new(a: int, b: int): Point*{
    return new Point{x: a, y: b};
  }

  func getX(self): int{
    return self.x;
  }
  func getY(self): int{
    return self.y;
  }
}

func classTest2(): int{
  return 123;
}