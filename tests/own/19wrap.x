import own/common

//B2 rule: a manual Drop impl runs for side effects, then derived glue
//frees every drop-typed struct field the body didn't free (Wrap.v is
//never touched by the custom body, yet must drop exactly once).
struct Wrap{
  v: A;
  n: i32;
}
impl Drop for Wrap{
  func drop(*self){
    print("custom drop\n");
  }
}
func make(){
  let w = Wrap{v: A::new(1), n: 0};
}
func main(){
  reset();
  make();
  check_ids(1);
  print("wrap done\n");
}
