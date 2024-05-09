func ptr(){
  let a: i32 = 5;
  let ptr: i32* = &a;
  assert *ptr == 5;
}

func main(){
  //normal
  let a: i32 = 10;
  assert a == 10;
  a = 20;
  assert a == 20;
  ptr();
  print("varTest done\n");
}