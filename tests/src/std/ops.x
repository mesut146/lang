trait Eq{
  func eq(self, x: Self): bool;
}

impl Eq for i32{
  func eq(self, x: i32): bool{
    return self == x;
  }
}
impl Eq for i64{
  func eq(self, x: i64): bool{
    return self == x;
  }
}