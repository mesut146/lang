import own/common

//Bindings from call temps that alias a borrowed argument: the borrowed
//place is consumed like a scrutinee (rollback restores the unescaped
//ones). Outer let-bound chains (let a = take_it(&o)) remain open: they
//need call-effect provenance, tracked separately.
enum E{
  V{v: A},
  W
}

//returns an alias of its argument (not a fresh value).
func get(o: E*): E {
  return *o;
}

func main(){
  //borrow-escape in if-let: binding moves out, owner suppressed.
  reset();
  esc_outer(E::V{v: A::new(1)});
  check_ids(1);

  //borrow-escape in match value.
  reset();
  esc_match(E::V{v: A::new(2)});
  check_ids(2);

  //inspect-only: binding suppressed, owner drops once.
  reset();
  inspect_call();
  check_ids(3);

  print("call temp done\n");
}

func esc_outer(o: E){
  if let E::V(s) = get(&o) {
    send(s);
  }
}

func esc_match(o: E){
  let x = match get(&o) {
    E::V(s) => s,
    _ => A::new(98)
  };
  send(x);
}

func inspect_call(){
  let o = E::V{v: A::new(3)};
  if let E::V(s) = get(&o) {
    assert(s.a == 3);
  }
}
