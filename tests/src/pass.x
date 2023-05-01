class A{
 a: i64;
 b: [i32; 100];
}

func by_val_mut(p: A){
  p.a = 11;
  assert p.a == 11;
}

func by_val_nomut(p: A){
  assert p.a == 10;
}

func by_val_arr(arr: [i32; 2]){
  print("arr %d %d\n", arr[0], arr[1]);
  assert arr[0] == 51;
}

func by_val_arr_mut(arr: [i32; 2]){
  print("arr %d %d\n", arr[0], arr[1]);
  arr[0] = 52;
  assert arr[0] == 52;
}

func main(){  
  let p = A{a: 10, b: [0; 100]};
  by_val_mut(p);
  assert p.a == 10;

  let arr = [51, 50];
  print("arr %d %d\n", arr[0], arr[1]);
  by_val_arr(arr);
  by_val_arr_mut(arr);
  print("arr %d %d\n", arr[0], arr[1]);
  assert arr[0] == 51;

  by_val_nomut(p);

  print("passTest done\n");
}