// should-fail: `null` is not a literal; use ptr::null<T>()
//`null` is no longer a keyword or a literal (2026-10-28). Using it as a value
//without declaring it points at the intrinsic instead of the generic
//"unknown identifier" message.
func main(){
  let p = null;
}
