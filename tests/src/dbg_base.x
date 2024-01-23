struct A{
    a: i32;
    b: i64;
}

struct B: A{
    c: i32;
    d: i32;
}

enum C: A{
    C1,
    C2(c: i32, d: i32)
}

func main(){
  let b = B{.A{a: 10, b: 20} , c: 30, d: 40};
  assert b.c == 30 && b.d == 40;
  let c = C::C1;
  let c2 = C::C2{.A{a:50,b:60}, c: 70,d:80};
  let x = c2.a;
}