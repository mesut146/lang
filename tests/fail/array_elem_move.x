// should-fail: cannot move out of an array element
//Only a *constant* index into a local array is a tracked element place now
//(Rhs::INDEX); a dynamic index has no place state, so a move out of it would
//leave the array dropping a value that already left. Use a copy, or move the
//whole array. (The same refusal covers slices, pointer bases, nested arrays,
//and fields of elements -- see array_elem_field_move.x.)
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
  let i = 0;
  send(arr[i]);
}
