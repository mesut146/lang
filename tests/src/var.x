func main(){
  let a: i32 = 5;
  assert a == 5;
  a = 6;
  assert a == 6;
  let ptr: i32* = &a;
  assert *ptr == 6;
  print("varTest done\n");
}