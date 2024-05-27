func main(){
  let o1 = Option<i32>::None;
  assert o1.is_none();
  //o1.unwrap(); //panics

  let o2 = Option<i32>::Some{5};
  assert o2.is_some();
  assert o2.unwrap() == 5;

  let num = 111;
  let o3 = Option::new(&num);
  assert *o3.unwrap() == 111;

  print("optional_test done\n");
}
