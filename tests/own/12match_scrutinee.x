import own/common

//Payload bindings copy the scrutinee's bytes, so the scrutinee must not
//drop them afterwards: named scrutinees get the same bind-time consume
//mark as temps (see consume_match_temp). Each case below double-dropped
//(= extra id) before the fix.
enum E{
  V{v: A},
  W
}

//return a payload binding out of the arm.
func take_it(o: E): A {
  match o {
    E::V(s) => {
      return s;
    },
    _ => {
      return A::new(99);
    }
  }
}

//yield a payload binding as the match value.
func yield_it(o: E): A {
  let x = match o {
    E::V(s) => s,
    _ => A::new(98)
  };
  return x;
}

//move a payload binding into an outer var, fall through (parser
//parse_obj shape: match param, move payload out, use after match).
func stash_it(o: E): A {
  let out = A::new(-1);
  match o {
    E::V(s) => {
      out = s;
    },
    _ => {}
  }
  return out;
}

func main(){
  //return-escape: payload moves to the caller, scrutinee must not drop.
  reset();
  let a = take_it(E::V{v: A::new(1)});
  check_ids();
  send(a);
  check_ids(1);

  //wildcard arm: scrutinee intact, nothing to drop; fresh return value.
  reset();
  let b = take_it(E::W);
  check_ids();
  send(b);
  check_ids(99);

  //match-value yield: same accounting as return-escape.
  reset();
  let c = yield_it(E::V{v: A::new(2)});
  check_ids();
  send(c);
  check_ids(2);

  //assign-outer + fallthrough: only the overwritten A(-1) drops here.
  reset();
  let d = stash_it(E::V{v: A::new(3)});
  check_ids(-1);
  reset();
  send(d);
  check_ids(3);

  //inspect-only: the binding copy is suppressed in-arm, the scrutinee
  //drops normally (no leak, no double).
  reset();
  inspect_e(E::V{v: A::new(4)});
  check_ids(4);

  print("match scrutinee done\n");
}

func inspect_e(e: E){
  match e {
    E::V(s) => {
      assert(s.a == 4);
    },
    _ => {}
  }
}
