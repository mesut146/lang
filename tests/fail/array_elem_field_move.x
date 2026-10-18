// should-fail: cannot move out of an array element
//A field of an *element* (`p[0].a`) is not a tracked place: its base has no
//vh, so Rhs::new leaves it untracked and the array would go on dropping that
//field -- the same allocation freed twice. This used to compile and drop the
//field twice (valgrind/ids showed two drops). Refuse it like every other
//untracked index place.
#drop
struct A{
  a: i32;
}
impl Drop for A{
  func drop(*self){
  }
}
struct P{
  a: A;
  b: A;
}
func send(a: A){
}
func main(){
  let p = [P{a: A{a: 1}, b: A{a: 2}}];
  send(p[0].a);
}
