import own/common

//Inspect-then-use: a binding that never escapes must not consume the
//scrutinee. The binding copy dies in-arm (suppressed), the scrutinee
//stays droppable AND usable afterwards: no leak, no false use-after-move.
enum E{
  V{v: A},
  W
}

func use_e(e: E){
}

func main(){
  //match inspect-use.
  reset();
  let e = E::V{v: A::new(1)};
  match e {
    E::V(s) => {
      assert(s.a == 1);
    },
    _ => {}
  }
  use_e(e);
  check_ids(1);

  //if-let inspect-use.
  reset();
  let f = E::V{v: A::new(2)};
  if let E::V(s) = f {
    assert(s.a == 2);
  }
  use_e(f);
  check_ids(2);

  //field scrutinee inspect-use twice: each binding copy is suppressed,
  //the scrutinee drops exactly once at scope end.
  reset();
  fldinspect(Wrp{e: E::V{v: A::new(3)}});
  check_ids(3);

  print("inspect use done\n");
}

func fldinspect(w: Wrp){
  match w.e {
    E::V(s) => {
      assert(s.a == 3);
    },
    _ => {}
  }
  match w.e {
    E::V(s) => {
      assert(s.a == 3);
    },
    _ => {}
  }
}

struct Wrp{
  e: E;
}
