struct A{
  a: i32;
}

struct B: A{
  b: i32;
}

enum E: A{
  E1,
  E2(a: i64)
}

func base_of_struct(){
  let b = B{.A{a: 10}, b: 20};
  assert b.a == 10;
  assert b.b == 20;
  //cast to base
  let a_ptr = b as A*;
  assert a_ptr.a == 10;
}
func base_of_struct2(){
  let a = A{a: 30};
  let b2 = B{.a, b: 40};
  assert b2.a == 30;
  assert b2.b == 40;
}
func base_of_enum(){
  let e = E::E1{.A{a: 30}};
  assert e is E::E1;
  assert e.a == 30;
  //cast to base
  let a_ptr = e as A*;
  assert a_ptr.a == 30;
}
func if_let(){
  let e = E::E2{.A{a: 50}, a: 60};
  assert e is E::E2;
  assert e.a == 50;
  if let E::E2(a) = (&e) {
    assert a == 60;
  }else{
    panic("if_let");
  }
  //cast to base
  let a_ptr = e as A*;
  assert a_ptr.a == 50;
}

func main(){
  base_of_struct();
  base_of_struct2();
  base_of_enum();
  if_let();
  print("base done\n");
}

