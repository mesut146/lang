struct A{
  a: i32;
  b: i64;
}

struct B{
  a: bool;
  b: i16;
}

func bool_test(){
 let a = B{false, 123i16};
 a.a = true;
 let aa = a.a;
}

impl A{
  func f1(self): i32{
    let a = self.a + 1;
    return a;
  }
}

func test(a: A*): i32{
    let b = a;
    let res = a.a + 1;
    return res;
}

func test2(a: A): i32{
  let b = a.a + 2;
  assert b == 52;
  return b;
}

func main(){
 bool_test();
 let a = A{50, 10};
 a.f1();
 test(&a);
 test2(a);
}