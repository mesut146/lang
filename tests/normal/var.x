func ptr(){
  let a: i32 = 5;
  let ptr: i32* = &a;
  assert *ptr == 5;
}

func main(){
  let a: i32 = 5;
  assert a == 5;
  a = 6;
  assert a == 6;
  ptr();
  print("varTest done\n");
}