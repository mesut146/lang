struct A<T>{
  val: T;
}

struct B<T, U>{
 a: T;
 b: U;
}

enum Op<T>{
  None,
  Some(val: T)
}

func one<T>(a: T, b: T): T{
  return a + b;
}

func two<T1, T2>(a: T1, b: T2): T1{
  return a + b;
}

//complex infer
func infera<T>(x: i32, a: A<T>): T{
  return x + a.val;
}

func inferb<T, U>(b: B<A<T>, U>): i64{
  return b.a.val + b.b;
}

func no_infer(){
  //specified
  assert(A<i32>{10}.val == 10);
  assert(A<A<i32>>{A<i32>{20}}.val.val == 20);
  let b = B<i32, A<i32>>{5, A<i32>{15}};
  assert(b.a == 5);
  assert(b.b.val == 15);

  assert(one<i32>(1, 2) == 3);
  assert(one<i64>(5, 6) == 11);
  assert(one<i64>(50, 60) == 110);//reuse

  assert(two<i32, i32>(7, 8) == 15);
  assert(two<i64, i32>(7, 8) == 15);

  assert(infera(1, A<i32>{val: 2}) == 3);
  assert(infera(3, A<i64>{val: 4}) == 7);
  assert(inferb(B<A<i32>, i64>{a: A<i32>{5}, b: 6}) == 11);

  let e = Op<i32>::Some{val: 5};
  if let Op<i32>::Some(val) = (e){
    assert(val == 5);
  }else{
    panic("error");
  }
}

func infer_struct(){
  assert(A{5}.val == 5);
  assert(A{A{10}}.val.val == 10);

  let b = B{15, A{20}};
  assert(b.a == 15);
  assert(b.b.val == 20);

  let b2 = B{A{25}, 30};
  assert(b2.a.val == 25);
  assert(b2.b == 30);
}

func inferTest(){
  infer_struct();
  assert(one(3, 4) == 7);//reuse
  //print("one=%d\n", one(5i64, 6i64));
  assert(one(5i64, 6i64) == 11);
  assert(two(9, 10) == 19);

  assert(infera(1, A{2i32}) == 3);
  assert(infera(3, A{4i64}) == 7);

  let b = B{A{50i32}, 60i32};
  printf("inferb(b)=%d\n", inferb(b));
  assert(inferb(b) == 110);
}

func main(){
  no_infer();
  inferTest();
  print("genericTest done\n");
}