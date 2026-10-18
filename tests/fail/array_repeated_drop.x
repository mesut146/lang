// should-fail: repeated array element type needs dropping
//`[e; n]` copies one value into n slots; a drop-typed element would become n
//aliases of one owned allocation (freed n times). Write the elements out.
#drop
struct A{
  a: i32;
}
impl Drop for A{
  func drop(*self){
  }
}
func main(){
  let arr = [A{a: 1}; 2];
  assert(arr.len() == 2);
}
