// should-fail: tuple struct index out of bounds
//Only t.0 exists on a one-field tuple struct; t.5 must be a diagnostic, not an
//out-of-range GEP.
struct T(i32);
func main(){
  let t = T{1};
  let x = t.5;
}
