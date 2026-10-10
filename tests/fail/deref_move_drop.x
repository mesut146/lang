// should-fail: move of drop type out of pointer without reassign
struct S{
  v: String;
}
func get(o: S*): S {
  return *o;
}
func main(){
}
