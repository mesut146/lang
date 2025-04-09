impl i32{
  func MIN(): i32{ return -2147483648; }
  func MAX(): i32{ return 2147483647; }

  func min(x1, y: i32): i32{
    if(*x1 <= y) return *x1;
    return y;
  }
  func max(x2, y: i32): i32{
    if(*x2 >= y) return *x2;
    return y;
  }
  func abs(x3): i32{
    if(*x3 >= 0) return *x3;
    return -*x3;
  }
  func generic_sum<T>(x4, y: T): T{
    return *x4 + y;
  }
  func generic_other<T>(x: T): T{
    return x;
  }

}

struct A<T>{
  a: T;
}

impl<T> A<T>{
  func get(self): T{
    return self.a;
  }
  func add(a: i32, b: i32): i32{
    return a + b;
  }
}

impl [i32]{
   func test(self){}
}

impl [i32; 3]{}

func main(){
  let x = 5;
  let neg = -5;
  assert(x.min(6) == 5);
  assert(x.max(6) == 6);
  assert(neg.abs() == 5);
  assert(x.generic_sum(6i64) == 11_i64);
  assert(i32::generic_other(5) == 5);
  assert(i32::min(&x, 6) == 5);

  assert(A<i32>{a: 5}.get() == 5);
  assert(A<i64>{a: 5}.get() == 5i64);
  //non member generic
  assert(A<i32>::add(5, 6) == 11);
  assert(A<i64>::add(5, 6) == 11);

  [1, 2, 3][0..3].test();
  print("implTest done\n");
}