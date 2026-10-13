// should-fail: move of drop type out of pointer without reassign
struct A{
  s: String;
}
func take(s: String){
}
func f(p: A*, c: bool){
  take(p.s);
  if(c){
    p.s = String::new("x");
  }
}
func main(){
}
