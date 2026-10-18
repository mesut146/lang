// should-fail: use after move
//Reading through an element that was moved out: the read goes through a
//dead place (the value is gone; the String case shows up as an invalid read
//at runtime -- here the drop-count tracker would show the element dropped
//twice).
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
  let n = arr[0].n;       //read through the dead element
  take(S{s: A{a: n}, n: n});
}
