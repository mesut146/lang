class A{
 a: int;
 b: int;
}

enum E{
 A,
 B(a: int, b: int),
 C(a: long);
}

func sum(a: int, b: int): int{
  return a + b;
}

func varTest(){
  let a: int = 5;
  assert a == 5;
  a = 6;
  assert a == 6;
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
  if let E::A = (a){
    print("a is E::A\n");
    //return;
  }else{
    print("a is not E::A\n");
  }
  let b: E = E::B{a: 5, b: 6};
  if let E::B(p1,p2) = (b){
    assert (p1==5)&&(p2==6);
    print("b is E::B a=%d b=%d\n",p1,p2);
    p1=10;
    print("b is E::B a=%d b=%d\n",p1,p2);
    assert (p1==10)&&(p2==6);
  }else{
    print("b is not E::B \n");
  }
  let c: E = E::C{100};
  if let E::C(p3) = (c){
    assert p3==100;
    print("c is E::C a=%ld\n", p3);
  }else print("c is not E::C\n");
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

func getTrue(cnt: int*): bool {
  print("getTrue\n");
  *cnt = *cnt + 1;
  return true;
}
func getFalse(cnt: int*): bool {
  print("getFalse\n");
  *cnt = *cnt + 1;
  return false;
}

func condTest(){
  let c1: int = 0;
  let c2: int = 0;
  assert (getFalse(&c2)&&getTrue(&c1))==false;
  assert c1 == 0 && c2 == 1;
 
  assert getTrue(&c1) && getTrue(&c1);
  assert c1 == 2 && c2 == 1;
  
  assert getTrue(&c1) || getFalse(&c2);
  assert c1==3 && c2==1;

  assert getFalse(&c2) || getTrue(&c1);
  assert c1==4&&c2==2;
}

func main(): int{
  varTest();
  condTest();
  infix();
  ifTest(4, 6);
  enumTest();
  //assert sum(2,3) == 5;
  //print("sum=%d\n", sum(2, 3));
  
  //assert *(&sum(5, 6)) == 11;
  /*let obj: A = A{a: 5, b: 6};
  print("A.a=%d, A.b=%d\n", obj.a, obj.b);
  obj.a=10;
  print("A.a=%d, A.b=%d\n", obj.a, obj.b);*/
  //let objCopy=obj.clone();
  
  return 0;
}
