// should-fail: use after move
//The struct-field counterpart of dead_elem_write.x: after `take(g.f)` the
//field is dead, so writing a part of it (`g.f.s = ..`) is a use after move.
//This used to compile and silently leak the written value.
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
  take(g.f);              //moved out: the field is dead now
  g.f.s = A{a: 2};        //write into the dead field
}
