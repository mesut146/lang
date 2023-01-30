impl i32{
  func MIN(): i32{ return -2147483648; }
  func MAX(): i32{ return 2147483647; }

  func min(x, y: i32): i32{
    if(x <= y) return x;
    return y;
  }
  func max(x, y: i32): i32{
    if(x >= y) return x;
    return y;
  }
  func abs(x): i32{
    if(x >= 0) return x;
    return -x;
  }
  func generic_sum<T>(x, y: T): T{
    return x + y;
  }
  func generic_other<T>(x: T): T{
    return x;
  }
}

class A<T>{
  a: T;
}

impl A<T>{
  func get(self): T{
    return self.a;
  }
  func add(a: i32, b: i32): i32{
    return a + b;
  }
}

func implTest(){
  let x = 5;
  assert x.min(6) == 5;
  assert 5.max(6) == 6;
  assert (-5).abs() == 5;
  assert 5.generic_sum(6i64) == 11;
  assert i32::generic_other(5) == 5;
  assert i32::min(5, 6) == 5;

  assert A<i32>{a: 5}.get() == 5;
  assert A<i64>{a: 5}.get() == 5;
  //non member generic
  assert A<i32>::add(5, 6) == 11;
  assert A<i64>::add(5, 6) == 11;

  print("implTest done\n");
}