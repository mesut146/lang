struct A{
 a: i32;
 b: i32;
}

enum E{
 A,
 B{a: i32, b: i32},
 C{a: i64},
 D{a: A}
}

#repr(i32)
enum F{
  A = 10,
  B = 20, 
  C
}

func test_repr(){
  let a = F::A;
  assert(a == 10);
  let a2 = a as i32;
  assert(a2 == 10);
  let b = F::B as i32;
  assert(b == 20);
  assert(F::C == 21);
  
  printf("enumcons=%d\n", F::A|F::B);
}

func main(){
  let a: E = E::A;
  let c: E = E::C{100};
  let d: E = E::D{A{a: 100, b: 200}};

  //let ss = a as i32;
  
  assert(a is E::A);
  assert(c is E::C);
  assert(d is E::D);

  let isA = false;
  let isC = false;
  let isD = false;
  if let E::A = (a){
    isA = true;
  }
  if let E::C(p3) = (c){
    isC = true;
    assert(p3 == 100);
  }
  assert(d is E::D);
  if let E::D(p4) = d{
    isD = true;
    assert(p4.a == 100 && p4.b == 200);
  }
  assert(isA);
  assert(isC);
  assert(isD);
  test_mut();
  test_repr();
  print("enumTest done\n");
}

func test_mut(){
  let isB = false;
  let b: E = E::B{b: 6, a: 5};//random order
  //let b: E = E::B{a: 5, b: 6};//random order
  assert(b is E::B);

  if let E::B(p1, p2) = b{
    isB = true;
    assert(p1 == 5);
    assert(p2 == 6);
    //mutate local var
    p1 = 10;
    assert(p1 == 10);
    assert(p2 == 6);
  }
  //mutate real
  if let E::B(p1, p2) = &b{
    assert(*p1 == 5 && *p2 == 6);
    *p1 = 10;
    assert(*p1 == 10 && *p2 == 6);
  }
  //check mutate
  if let E::B(p100, p200) = b{
    assert(p100 == 10 && p200 == 6);
  }else{
    panic("mut");
  }
  assert(isB);
}