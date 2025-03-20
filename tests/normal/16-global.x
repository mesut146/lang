static x: i32 = 11;

#derive(Debug)
struct A{
  a: i32;
  b: i64;
  c: i64;
}

static a: A = A{a: 10, b: 20, c: 30};

func main(){
  assert(x == 11);
  x = 22;
  assert(x == 22);


  print("a={:?}\n", a);
  assert(a.a == 10);
  assert(a.b == 20);
  assert(a.c == 30);
  a.c = 40;
  assert(a.a == 10);
  assert(a.b == 20);
  assert(a.c == 40);
}