import own/common

#[returns_alias(p)]
func ident_a(p: A*): A{
  //over-claims on purpose (no real aliasing here): the annotation is
  //conservative, the owner is consumed anyway. Pins the mechanism.
  return A::new(99);
}
//unused extern decl pins attribute parsing on extern members (never
//called, so nothing to link).
extern{
  #[returns_alias(q)]
  func ef(q: A*): A;
}
//drop-on-assign pin: the consumed owner never drops, the fresh return
//drops exactly once.
func main(){
  let o = A::new(1);
  let a = ident_a(&o);
  a.check(99);
  check_ids();
  reset();
  send(a);
  check_ids(99);
  print("alias done\n");
}
