// should-fail: borrow of a named place
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
  let a = ident_a(&A{v: 1});
  use(a);
}
