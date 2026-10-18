// should-fail: use after move
//A second move of a field that was already moved out. Same hole as
//dead_elem_move.x, one level up: the field place is dead, so the move is a
//use after move (it used to compile and double free at runtime).
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
struct F{
  f: S;
}
func take(x: S){
}
func main(){
  let g = F{f: S{s: A{a: 1}, n: 1}};
  take(g.f);              //first move: the field is dead now
  let y = g.f;            //second move of the dead field
  take(y);
}
