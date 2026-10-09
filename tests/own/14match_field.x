import own/common

//match on a field: return-escape, fallthrough, inspect-only.
enum E{
  V{v: A},
  W
}
struct Wrp{
  e: E;
}

func fldtake(w: Wrp): A {
  match w.e {
    E::V(s) => {
      return s;
    },
    _ => {
      return A::new(99);
    }
  }
}

func fldfall(w: Wrp): A {
  let out = A::new(-1);
  match w.e {
    E::V(s) => {
      out = s;
    },
    _ => {}
  }
  return out;
}

func main(){
  //return-escape: payload moves out, whole scrutinee leaks (no drop).
  reset();
  let a = fldtake(Wrp{e: E::V{v: A::new(1)}});
  check_ids();
  send(a);
  check_ids(1);

  //non-matching: scrutinee drops normally.
  reset();
  let b = fldtake(Wrp{e: E::W});
  check_ids();
  send(b);
  check_ids(99);

  //fallthrough with move to outer var.
  reset();
  let c = fldfall(Wrp{e: E::V{v: A::new(2)}});
  check_ids(-1);
  reset();
  send(c);
  check_ids(2);

  //inspect-only: binding suppressed, scrutinee drops normally.
  reset();
  inspect14(Wrp{e: E::V{v: A::new(3)}});
  check_ids(3);

  print("field done\n");
}

func inspect14(w: Wrp){
  match w.e {
    E::V(s) => {
      assert(s.a == 3);
    },
    _ => {}
  }
}
