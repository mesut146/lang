class A{
 a: i32;
 b: i32;
}

class B{
 a: A;
 c: i32;
}

enum E{
 A,
 B(a: i32, b: i32),
 C(a: i64),
 A2(a: A)
}

func structTest(){
  //random order
  let obj = A{b: 6, a: 5};
  assert obj.a == 5 && obj.b == 6;
  obj.a = 10;
  assert obj.a == 10 && obj.b == 6;

  let b = B{a: obj, c: 3};
  assert b.c == 3;
  assert b.a.a == 10 && b.a.b == 6;

  print("structTest done\n");
  enumTest();
}

func enumTest(){
  let a: E = E::A;
  let b: E = E::B{b: 6, a: 5};//random order
  let c: E = E::C{100};
  let d: E = E::A2{A{a: 100, b: 200}};
  assert a.index == 0;
  assert b.index == 1;
  assert c.index == 2;
  assert a is E::A && b is E::B && c is E::C && d is E::A2;

  let isA = false;
  let isB = false;
  let isC = false;
  let isD = false;
  if let E::A = (a){
    isA = true;
  }
  if let E::B(p1, p2) = (b){
    isB = true;
    assert p1 == 5 && p2 == 6;
    p1 = 10;
    assert p1 == 10 && p2 == 6;
  }
  if let E::C(p3) = (c){
    isC = true;
    assert p3 == 100;
  }
  if let E::A2(p4) = (d){
    isD = true;
    assert p4.a == 100 && p4.b == 200;
  }
  assert isA;
  assert isB;
  assert isC;
  assert isD;
  print("enumTest done\n");
}

