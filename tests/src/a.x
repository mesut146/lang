func sum(a: int, b: int): int{
  return a + b;
}

class A{
 a: int;
 b: int;
}

enum E{
 A,
 B(a: int, b: byte),
 C(a: long);
}

func main(): int{
  assert sum(2,3) == 5;
  print("%d", sum(2, 3));
  let a: int = 5;
  let ptr: int* = &a;
  assert *ptr == 5;
  //assert *(&sum(5, 6)) == 11;
  let obj: A = A{a: 5, b: 6};

  let en: E = E::B{a: 5, b: 6};
  let en2: E = E::C{10};
  return 0;
}
