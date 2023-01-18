class A{
 a: long;
 b: [int; 100];
}

func by_val_mut(p: A){
  p.a = 11;
  assert p.a == 11;
}
func by_val_nomut(p: A){
  assert p.a == 10;
}

func passTest(){
  let arr = [0; 100];
  let p = A{a: 10, b: arr};
  by_val_mut(p);
  assert p.a == 10;

  by_val_nomut(p);

  print("passTest done\n");
}