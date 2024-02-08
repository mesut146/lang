class A{
  a: B;
}

class B{
  a: i32;
}

func getA(): A{
  return A{B{5}};
}

func main(){
  let a = getA().a;
  assert a.a == 5;
  print("allocTest done\n");
}