struct Point{
  x: i32;
  y: i32;
}

impl Point{
  func new(a: i32, b: i32): Point{
    return Point{x: a, y: b};
  }
  func getX(self): i32{
    return self.x;
  }
  func getY(self): i32{
    return self.y;
  }
}