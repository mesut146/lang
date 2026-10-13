#drop
struct Inner{
  v: i32;
}
impl Drop for Inner{
  func drop(*self){
  }
}
struct Outer{
  inner: Inner;
  n: i32;
}
func take(x: Inner){
}

//conditional move healed unconditionally after: sound on both paths
//(taken: moved then healed; skipped: heal overwrites the live value).
func condmove(p: Outer*, c: bool){
  if(c){
    take(p.inner);
  }
  p.inner = Inner{v: 9};
}
func main(){
  let o = Outer{inner: Inner{v: 1}, n: 2};
  condmove(&o, true);
  condmove(&o, false);
  print("cond done\n");
}
