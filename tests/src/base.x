struct A{
  a: i32;
}

struct B:A{
  b: i32;
}

enum E: A{
  E1,
  E2
}

fn main(){
  let b = B{.A{a: 10}, b: 20};
  assert b.b == 20;
  assert b.a == 10;

  let a = A{a: 30};
  let b2 = B{.a, b: 40};
  assert b2.a == 30;
  assert b2.b == 40;

  let a2 = b as A*;
  assert a2.a == 10;

  let e = E::E1{.A{a: 30}};
  assert e.a == 30;

  print("base done\n");
}

