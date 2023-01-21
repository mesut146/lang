class A{
 a: int;
 b: int;
}

class B{
 a: A;
 c: int;
}

enum E{
 A,
 B(a: int, b: long),
 C(a: long);
}

func classTest(){
  //random order
  let obj = A{b: 6, a: 5};
  assert obj.a == 5 && obj.b == 6;
  obj.a = 10;
  assert obj.a == 10 && obj.b == 6;

  let b = B{a: obj, c: 3};
  assert b.c == 3;
  assert b.a.a == 10 && b.a.b == 6;

  print("classTest done\n");
}

func enumTest(){
  let a: E = E::A;
  let b: E = E::B{b: 6, a: 6};
  let c: E = E::C{100};

  assert a.index == 0 && b.index==1 && c.index == 2;
  assert a is E::A && b is E::B && c is E::C;

  let isA = false;
  let isB = false;
  let isC = false;
  if let E::A = (a){
    isA = true;
  }
  if let E::B(p1,p2) = (b){
    isB = true;
    assert p1 == 5 && p2 == 6;
    p1 = 10;
    assert p1 == 10 && p2 == 6;
  }
  if let E::C(p3) = (c){
    isC = true;
    assert p3 == 100;
  }
  assert isB;
  assert isA;
  assert isC;
  print("enumTest done\n");
}

