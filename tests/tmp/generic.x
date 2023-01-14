func oneT<T>(a: T, b: T): T{
  return a + b;
}

func twoT<T1,T2>(a: T1, b: T2): T1{
  return a + b;
}

func genericTest(){
  assert oneT<int>(5, 6) == 11;
  assert oneT<long>(50, 60) == 110;
  assert twoT<int,int>(10, 20) == 30;
  assert twoT<long,int>(10, 21) == 31;
  print("genericTest done\n");
}