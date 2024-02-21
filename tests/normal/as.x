func prim(){
  let a: i32 = 5;
  //extend
  let b = a as i64;
  assert b == 5;
  //trunc
  let c = a as i8;
  assert c == 5;
}

class A{
  a: i64;
  b: i64;
}

class B: A{
  c: i32;
}

func base(){
  let b = B{.A{10, 20}, 30};
  //bitcast
  let a = b as A*;
  assert a.a == 10 && a.b == 20;
}

func main(){
  prim();
  base();
  print("as done\n");
}