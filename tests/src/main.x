import classTest
import infix
import enumTest
import flow
import generic
import List
import Box
import map
import array
import pass
import ret
import impl
import Option
import str
import libc
import alloc
import traits
import parser/lexer
import parser/parser

func literalTest(){
  let a8 = 5i8;
  let a16 = 5i16;
  let a32 = 5i32;
  let a64 = 5i64;
  assert a8 == 5 && a16 == 5 && a32 == 5 && a64 == 5;
  print("literalTest done\n");
}

func varTest(){
  let a: i32 = 5;
  assert a == 5;
  a = 6;
  assert a == 6;
  let ptr: i32* = &a;
  assert *ptr == 6;
  print("varTest done\n");
}

func getTrue(cnt: i32*): bool {
  *cnt = *cnt + 1;
  return true;
}
func getFalse(cnt: i32*): bool {
  *cnt = *cnt + 1;
  return false;
}

func condTest(){
  let c1: i32 = 0;
  let c2: i32 = 0;
  assert (getFalse(&c2)&&getTrue(&c1))==false;
  assert c1 == 0 && c2 == 1;
 
  assert getTrue(&c1) && getTrue(&c1);
  assert c1 == 2 && c2 == 1;
  
  assert getTrue(&c1) || getFalse(&c2);
  assert c1==3 && c2==1;

  assert getFalse(&c2) || getTrue(&c1);
  assert c1==4 && c2==2;
  
  assert (getFalse(&c2) || getTrue(&c1)) && getTrue(&c1);
  assert (getTrue(&c1) && getFalse(&c2)) || getTrue(&c1);
  assert getFalse(&c2) || (getTrue(&c1) && getTrue(&c1));
  assert getTrue(&c1) && (getFalse(&c2) || getTrue(&c1));

  print("condTest done\n");
}

func prims(){
  for(let i = 3 ; i < 90 ; i = i + 2){
    let pr = true;
    for (let j = 3; j * j < i; j = j + 2){
      if(i % j == 0){
        pr = false;
        break;
      }
    }
    if(pr) print("%d, ", i);
  }
  print("prims done\n");
}

func mallocTest(){
   let arr = malloc<i32>(10);
   arr[0] = 3;
   arr[1] = 5;
   assert arr[0] == 3 && arr[1] == 5;
   mallocTest2();
   print("mallocTest done\n");
}

class Big{
  a: i64;
  b: i64;
}

func mallocTest2(){
   let arr = malloc<Big>(2);
   arr[0] = Big{5, 25};
   arr[1] = Big{6, 36};
   assert arr[0].a == 5 && arr[0].b == 25;
   assert arr[1].a == 6 && arr[1].b == 36;
}

func importTest(){
  //from classTest
  let c = Point{x: 100, y: 200};
  assert c.x == 100 && c.y == 200;

  let c2 = Point::new(10, 20);
  assert c2.getX() == 10 && c2.getY() == 20;
  
  print("importTest done\n");
}

func main(): i32{
  literalTest();
  varTest();
  condTest();
  infixTest();
  flowTest();
  structTest();
  baseTest();
  mallocTest();
  prims();
  importTest();
  genericTest();
  listTest();
  boxTest();
  arrayTest();
  passTest();
  retTest();
  implTest();
  optionalTest();

  strTest();
  libc_test();
  allocTest();
  traitTest();
  map_test();
  lexer_test();
  //Parser::test();
  return 0;
}
