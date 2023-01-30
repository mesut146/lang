import classTest
import infix
import enumTest
import flow
import generic
import List
import array
import pass
import ret
import impl
import optional
import str

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

  print("condTest done\n");
}

func prims(){
  let i = 3;
  while(i < 100){
    let pr = true;
    let j = 3;
    while (j * j < i){
      if(i % j==0){
        pr = false;
        break;
      }
      j = j + 2;
    }
    if(pr)
      print("%d, ", i);
    i = i + 2;
  }
  print("prims done\n");
}


func mallocTest(){
   let arr = malloc<i32>(10);
   arr[0] = 3;
   arr[1] = 5;
   assert arr[0] == 3 && arr[1] == 5;
   print("mallocTest done\n");
}


func importTest(){
  //from classTest
  let c = Point{x: 100, y: 200};
  assert c.x == 100 && c.y == 200;

  /*let c2 = Point::new(10, 20);
  assert c2.getX() == 10 && c2.getY() == 20;*/
  
  assert classTest2() == 123;
  print ("importTest done\n");
}

func main(): i32{
  literalTest();
  varTest();
  condTest();
  infixTest();
  ifTest();
  elseTest();
  enumTest();
  classTest();
  mallocTest();
  whileTest();
  prims();
  importTest();
  genericTest();
  listTest();
  arrayTest();
  passTest();
  retTest();
  implTest();
  optionalTest();

  strTest();

  return 0;
}
