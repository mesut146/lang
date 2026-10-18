// should-fail: cannot move out of an array element
//An index place is not tracked like a field, so a move out of an array
//element would leave the array dropping a value that already left. Use a
//copy, or move the whole array.
#drop
struct A{
  a: i32;
}
impl Drop for A{
  func drop(*self){
  }
}
func send(a: A){
}
func main(){
  let arr = [A{a: 1}, A{a: 2}];
  send(arr[0]);
}
