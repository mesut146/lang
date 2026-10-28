// should-fail: tuple struct fields are positional
//`struct T(i32);` has no field names, so `T{a: 1}` cannot be matched by name.
//Construction is the unnamed-entry form `T{1}`.
struct T(i32);
func main(){
  let t = T{a: 1};
}
