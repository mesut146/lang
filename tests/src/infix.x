func infixTest(){
  let a: i32 = 2;
  let b: i32 = 11;
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
  let x: i32 = 10;
  let y: i64 = 11;
  assert x + y == 21;

  print("infixTest done\n");
}