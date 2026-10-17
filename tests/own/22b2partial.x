import own/common

//B2 per-field: a manual Drop body that names only some fields must not
//suppress the derived free of the others. The body here frees `kept` itself;
//`owned` is never named, so the appended derived free must still drop it
//exactly once. Pre-fix (any self touch suppressed every field) `owned` was
//never dropped and check_ids failed.
struct Partial{
  owned: A;
  kept: B;
}
impl Drop for Partial{
  func drop(*self){
    Drop::drop(self.kept);
  }
}
func make(){
  let p = Partial{owned: A::new(1), kept: B::new(2)};
}
func main(){
  reset();
  make();
  //body first (kept -> 2), then the appended derived free (owned -> 1)
  check_ids(2, 1);
  print("b2partial done\n");
}
