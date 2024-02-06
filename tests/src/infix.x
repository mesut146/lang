func main(){
  let a: i32 = 2;
  let b: i32 = 11;
  assert a+3==5;
  assert a*5==10;
  /*assert 10-a==8;
  assert 6/a==3;
  assert 15 % (a*a) == 3;
  assert (14 & b) == 10;
  assert (14 | b) == 15 ;
  assert (14^b)==5;
  assert (a<<3)==16;
  assert (b>>1)==5;*/
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
  let x: i32 = 10;
  let y: i64 = 11;
  assert x + y == 21;

  print("infixTest done\n");
  
  condTest();
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