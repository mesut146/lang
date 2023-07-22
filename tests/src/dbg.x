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
  func myfunc(self){
    let a = self.a + 1;
  }
}

func test(a: A*){
    let b = a;
    let res = a.a + 1;
}

func test2(a: A){
  let b = a.a + 2;
  assert b == 52;
}

func main(){
 bool_test();
 let a = A{50, 10};
 let aa = a.a;
 let b = &a;
 let bb = b.b;
 let l = List<i32>::new();
 l.add(55);

 a.myfunc();
 test(&a);
 test2(a);
}