func one<T>(a: T, b: T): T{
  return a + b;
}

func two<T1, T2>(a: T1, b: T2): T1{
  return a + b;
}

class A<U>{
  val: U;
}

//complex infer
func infer<U>(x: i32, y: A<i8>, a: A<U>): U{
  return a.val;
}

/*func infer<T1, T2>(a: T1): T2{
  return a as T2;
}

func infer2<T1, T2>(a: T2): T1{
  return a as T1;
}*/

func genericTest(){
  //specified
  assert one<i32>(1, 2) == 3;
  //inferred
  assert one(3, 4) == 7;//reuse
  //specified
  assert one<i64>(5, 6) == 11;
  assert one<i64>(50, 60) == 110;
  //infer
  assert one(5 as i64, 6 as i64) == 11;
  //specified
  assert two<i32, i32>(7, 8) == 15;
  assert two<i64, i32>(7, 8) == 15;//reuse
  //inferred
  assert two(9, 10) == 19;
  //assert infer(1, A<i8>{val: 2}, A<i32>{val: 55}) == 55;
  //assert infer(1, A<i8>{val: 2}, A<i64>{val: 55}) == 55;

  print("genericTest done\n");
}