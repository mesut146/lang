class A{
  a: B;
}

class B{
  a: i32;
}

func getA(): A{
  return A{B{5}};
}

func allocTest(){
  let a = getA().a;
  assert a.a == 5;
  //let c = getA().c;
  print("allocTest done\n");
}