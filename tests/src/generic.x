func one<T>(a: T, b: T): T{
  return a + b;
}

func two<T1, T2>(a: T1, b: T2): T1{
  return a + b;
}

class A<T>{
  val: T;
}

class B<T, U>{
 a: T;
 b: U;
}

enum Op<T>{
  None,
  Some(val: T)
}

//complex infer
func infer<T>(x: i32, a: A<T>): T{
  return x + a.val;
}

func infer2<T, U>(b: B<A<T>, U>): i64{
  return b.a.val + b.b;
}

func genericTest(){
  //specified
  assert one<i32>(1, 2) == 3;
  assert one<i64>(5, 6) == 11;
  assert one<i64>(50, 60) == 110;//reuse

  assert two<i32, i32>(7, 8) == 15;
  assert two<i64, i32>(7, 8) == 15;

  assert infer(1, A<i32>{val: 2}) == 3;
  assert infer(3, A<i64>{val: 4}) == 7;
  assert infer2(B<A<i32>, i64>{a: A<i32>{5}, b: 6}) == 11;

  let e = Op<i32>::Some{val: 5};
  if let Op<i32>::Some(val) = (e){
    assert val == 5;
  }else{
    panic("error");
  }

  inferTest();
  print("genericTest done\n");
}

func inferTest(){
  assert one(3, 4) == 7;//reuse
  assert one(5i64, 6i64) == 11;
  assert two(9, 10) == 19;

  assert infer(1, A{2}) == 3;
  assert infer(3, A{4i64}) == 7;
  assert infer2(B{a: A{5}, b: 6}) == 11;

  assert A{5}.val == 5;
  assert A{A{5}}.val.val == 5;
  assert B{5, A{6}}.b.val == 6;
}
