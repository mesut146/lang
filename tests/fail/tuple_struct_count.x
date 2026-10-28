// should-fail: field count mismatch
//Every positional field must be supplied: two slots, one value.
struct T(i32, i32);
func main(){
  let t = T{1};
}
