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
  //print("*ptr=%d\n", *ptr);

  print("varTest done\n");
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
  assert (14 | b) == 15 ;
  assert (14^b)==5;
  assert (a<<3)==16;
  assert (b>>1)==5;
  //unary
  assert -a == -2;
  //++infix();
  assert ++a == 3;
  assert a == 3;
  assert --a == 2;
  assert a == 2;
  a += 1;
  assert a == 3;

  //implicit cast
  let x: int = 10;
  let y: long = 11;
  assert x + y == 21;

  print("infix done\n");
}

func enumTest(){
  let a: E = E::A;
  let b: E = E::B{a: 5, b: 6};
  let c: E = E::C{100};

  assert a.index == 0 && b.index==1 && c.index == 2;
  assert a is E::A && b is E::B && c is E::C;

  if let E::A = (a){
    print("a is E::A\n");
  }
  if let E::B(p1,p2) = (b){
    assert (p1==5)&&(p2==6);
    //print("b is E::B a=%d b=%d\n",p1,p2);
    p1=10;
    //print("b is E::B a=%d b=%d\n",p1,p2);
    assert (p1==10)&&(p2==6);
  }
  if let E::C(p3) = (c){
    assert p3 == 100;
    print("c is E::C a=%ld\n", p3);
  }
  print("enumTest done\n");
}

func ifTest(){
  let b = true;
  let inIf = false;
  let inElse = false;
  if(b){
    inIf = true;
  }else{
    inElse = true;
  }
  assert inIf;
  assert inElse == false;
  
  print("ifTest done\n");
}

func elseTest(){
  let b = false;
  let inIf = false;
  let inElse = false;
  if(b){
    inIf = true;
  }else{
    inElse = true;
  }
  assert inElse;
  assert inIf == false;
  
  print("elseTest done\n");
}

func getTrue(cnt: int*): bool {
  //print("getTrue\n");
  *cnt = *cnt + 1;
  return true;
}
func getFalse(cnt: int*): bool {
  //print("getFalse\n");
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
  assert c1==4 && c2==2;

  print("condTest done\n");
}

func classTest(){
//  let obj: A = A{a: 5, b: 6};
  let obj: A = A{b: 6, a: 5};
  assert obj.a == 5 && obj.b == 6;
  obj.a=10;
  assert obj.a == 10 && obj.b == 6;
  //let objCopy=obj.clone();

  let b = B{a: obj, c: 3};
  assert b.c == 3;
  assert b.a.a == 10 && b.a.b == 6;

  print("classTest done\n");
}

class List<T>{
  size: int;
  cap: int;
  ptr: T*;
}

func newList<T>(): List<T>*{
  let res = new List<T>{size: 0, cap: 10, ptr: malloc<T>(10)};
  return res;
}

func add<T>(list: List<T>*, val: T){
 list.ptr[list.size] = val;
 ++list.size;
}

func get<T>(list: List<T>*, idx: int): T{
 return list.ptr[idx];
}

func printList<T>(list: List<T>*){
  print("size=%d cap=%d\n", list.size, list.cap);
  let i = 0;
  print("[");
  while(i < list.size){
    print("%d ", get<int>(list, i));
  }
  print("]");
}

func listTest(){
  let list = newList<int>();
  add<int>(list, 5);
  //add<int>(list, 7);
  printList<int>(list);
  print ("listTest done\n");
}

func mallocTest(){
   //malloc(10 as long);
   //let p = null;
   //malloc<int>(10 as long);

   let arr = malloc<int>(10);
   arr[0]=3;
   arr[1]=5;
   print("arr: %d, %d\n", arr[0], arr[1]);

   print("mallocTest done\n");
}

func whileTest(){
  let i = 0;
  while(i < 10){
    if(i%2==0) {
      ++i;
      continue; 
    }
    print("i=%d, ", i);
    ++i;
  }
  print("\nwhileTest done\n");
}

func main(): int{
  varTest();
  condTest();
  infix();
  ifTest();
  elseTest();
  enumTest();
  classTest();
  mallocTest();
  listTest();
  whileTest();
  //assert sum(2,3) == 5;
  //print("sum=%d\n", sum(2, 3));
  //assert *(&sum(5, 6)) == 11;
  return 0;
}
