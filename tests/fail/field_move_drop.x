// should-fail: move of drop type out of pointer without reassign
struct A{
  s: String;
}
func take(s: String){
}
func f(p: A*){
  take(p.s);
}
func main(){
}
