// should-fail: use after move
#drop
struct A{
  v: i32;
}
impl Drop for A{
  func drop(*self){
  }
}
#[returns_alias(p)]
func ident_a(p: A*): A{
  return A{v: 99};
}
func use(a: A){
}
func main(){
  let o = A{v: 1};
  let a = ident_a(&o);
  use(a);
  use(o);
}
