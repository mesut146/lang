func one<T>(a: T, b: T): T{
  return a + b;
}

func two<T1,T2>(a: T1, b: T2): T1{
  return a + b;
}

func genericTest(){
  assert one<i32>(5, 6) == 11;
  assert one<i64>(50, 60) == 110;
  assert two<i32, i32>(10, 20) == 30;
  assert two<i64, i32>(10, 21) == 31;
  print("genericTest done\n");
}