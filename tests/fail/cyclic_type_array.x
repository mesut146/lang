// should-fail: cyclic type S
//Same cycle through an array field: `is_drop_rt` recurses into the element
//type. A *pointer* field would break the cycle and stay legal (`s: S*`).
struct S{
  a: [S; 3];
}
func main(){
}
