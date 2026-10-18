// should-fail: cyclic type S
//Same cycle through a *tuple* field: `is_drop_rt` recurses into the tuple
//elements and re-enters S (the pre-fix crash shape reported in handoff.md).
struct S{
  t: (S, i32);
}
func main(){
}
