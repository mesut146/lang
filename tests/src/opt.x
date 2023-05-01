func main(){
  let o1 = Option<i32>::None;
  assert o1.is_none();
  //o1.unwrap(); //panics

  let o2 = Option<i32>::Some{5};
  assert o2.is_some();
  assert o2.unwrap() == 5;

  print("optionalTest done\n");
}
