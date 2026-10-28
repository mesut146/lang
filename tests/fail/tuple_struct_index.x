// should-fail: tuple struct index not int
//The field of `struct T(i32);` is selected by number (t.0); a name has nothing
//to bind to.
struct T(i32);
func main(){
  let t = T{1};
  let x = t.a;
}
