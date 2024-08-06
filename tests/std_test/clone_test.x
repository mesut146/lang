#derive(Clone, Debug)
struct A{
  a: i32;
  b: i32*;
  c: B;
}

#derive(Clone, Debug)
struct B{
  d: i32;
}

#derive(Clone, Debug)
enum E{
    E1(a: i32, b: i32*, c: B),
    E2
}

func main(){
  let x = 10;
  let b = B{20};
  let a = A{a: 5, b: &x, c: b};
  let a2 = a.clone();
  let a_str = Fmt::str(&a);
  let a2_str = Fmt::str(&a2);
  assert_eq(&a_str, &a2_str);
  a_str.drop();
  a2_str.drop();

  let e1 = E::E1{a: 5, b: &x, c: b};
  let e1_clone = e1.clone();
  let e1_str = Fmt::str(&e1);
  let e1c_str = Fmt::str(&e1_clone);
  assert_eq(&e1_str, &e1c_str);
  e1_str.drop();
  e1c_str.drop();

  let e2 =  E::E2;
  let e2_clone = e2.clone();
}