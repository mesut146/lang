// should-fail: use after move
//A second move of an element that was already moved out: the first take owns
//the value (and frees it), so the second hands the callee the same bytes
//again (invalid read + double free at runtime). The element place is dead,
//so the move is a use after move.
#drop
struct A{
  a: i32;
}
impl Drop for A{
  func drop(*self){
  }
}
struct S{
  s: A;
  n: i32;
}
func take(x: S){
}
func main(){
  let arr = [S{s: A{a: 1}, n: 1}];
  take(arr[0]);           //first move: the element is dead now
  let y = arr[0];         //second move of the dead element
  take(y);
}
