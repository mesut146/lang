// should-fail: use after move
//Writing into a field of an element that was moved out (`take(arr[0])` then
//`arr[0].s = ..`) used to compile and silently leak the value written in:
//the element place is dead, so a *partial* write is a use after move
//(Own::check_place). Only a whole-place write (`arr[0] = ..`) reinitializes
//the element and stays legal (see own/29arrmove.x).
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
  take(arr[0]);           //moved out: the element is dead now
  arr[0].s = A{a: 2};     //write into the dead element
}
