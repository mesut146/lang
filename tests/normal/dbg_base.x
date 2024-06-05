struct A{
    a: i32;
    b: i64;
}
func getA(a: i32, b: i32): A{
    return A{a, b};
}

struct B: A{
    c: i32;
    d: i32;
}

enum C: A{
    C1,
    C2(x: i32, y: i32)
}

func main(){
  let b = B{.A{a: 10, b: 20} , c: 30, d: 40};
  assert(b.c == 30 && b.d == 40);
  let c = C::C1{.A{a: 100, b: 200}};
  let c2 = C::C2{.A{a:50, b:60}, x: 70, y: 80};
  let x = c2.a;
}