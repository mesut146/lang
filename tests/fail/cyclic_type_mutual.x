// should-fail: cyclic type A
//Mutual value recursion: neither decl alone contains itself, the cycle is
//A -> B -> A. The drop query walks both decls, so it needs the same guard
//as the direct case.
struct A{
  b: B;
}
struct B{
  a: A;
}
func main(){
}
