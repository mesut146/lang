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

func by_val_arr(arr: [int; 100]){
  assert arr[0] == 51;
}

func by_val_arr_mut(arr: [int; 100]){
  arr[0] = 52;
  assert arr[0] == 52;
}

func passTest(){
  let arr = [0; 100];
  arr[0] = 51;
  let p = A{a: 10, b: arr};
  by_val_mut(p);
  assert p.a == 10;

  by_val_arr(arr);
  by_val_arr_mut(arr);
  assert arr[0] == 51;

  by_val_nomut(p);

  print("passTest done\n");
}