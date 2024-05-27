func main(){
  let arr = List<i32>::new();
  arr.add(10);
  arr.add(20);
  arr.add(30);
  let a = arr.get_ptr(0);
  print("a = {}\n", a);
}