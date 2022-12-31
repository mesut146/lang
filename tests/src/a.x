class A{
 a: int;
 b: int;
}

enum E{
 A,
 B(a: int, b: byte),
 C(a: long);
}

func sum(a: int, b: int): int{
  return a + b;
}

func varTest(){
  let a: int = 5;
  print("a=%d a+1=%d\n", a, a+1);
  assert a == 5;

  a = 6;
  print("a=6=>%d\n", a);

  let ptr: int* = &a;
  assert *ptr == 6;
  print("*ptr=%d\n", *ptr);
}

func infix(){
  let a: int = 2;
  let b: int = 11;
  assert a+3==5;
  assert a*5==10;
  assert 10-a==8;
  assert 6/a==3;
  assert 15 % (a*a) == 3;
  assert (14 & b) == 10;
  assert (14 | b) ==15 ;
  assert (14^b)==5;
  assert (a<<3)==16;
  assert (b>>1)==5;
}

func enumTest(){
  let a: E = E::A;
  let b: E = E::B{a: 5, b: 6};
  //let c: E = E::C{10};

  if let E::A = (a){
    print("a is E::A\n");
  }else{
    print("a is not E::A\n");
  }
  if let E::B(p1,p2) = (b){
    print("b is E::B a=%d b=%d\n",p1,p2);
    p1=10;
    print("b is E::B a=%d b=%d\n",p1,p2);
  }else{
    print("b is not E::B \n");
  }
}

func ifTest(x: int, y: int){
 if(x<5){
    print("%d < 5\n", x);
 }
 print("after if\n");
 if(y<6){
    print("%d < 6\n", y);
 }else{
    print("in else(!(%d<6))\n", y);
 }
 print("after 2nd if\n");
}

func main(): int{
  varTest();
  infix();
  ifTest(4, 6);
  assert sum(2,3) == 5;
  print("sum=%d\n", sum(2, 3));
  
  //assert *(&sum(5, 6)) == 11;
  let obj: A = A{a: 5, b: 6};
  print("A.a=%d, A.b=%d\n", obj.a, obj.b);
  obj.a=10;
  print("A.a=%d, A.b=%d\n", obj.a, obj.b);
  //let objCopy=obj.clone();
  enumTest();
  return 0;
}
