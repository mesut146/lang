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

//move out of pointer heals by reassign (see doc/move_ptr_field.txt);
//non-drop derefs and ptr::deref stay free.
func main(){
  let o = Outer{inner: Inner{v: 1}, n: 2};
  let p = &o;
  take(p.inner);
  p.inner = Inner{v: 3};
  assert(o.n == 2);

  let n = 5;
  let pn = &n;
  let m = *pn;
  assert(m == 5);

  let q = &o;
  assert(ptr::deref!(q).n == 2);

  print("ptr move done\n");
}
