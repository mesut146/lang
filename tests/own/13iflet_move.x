import own/common

//if-let variants: return-escape, fallthrough+post-use, inspect-only.
enum E{
  V{v: A},
  W
}

func iftake(o: E): A {
  if let E::V(s) = o {
    return s;
  }
  return A::new(99);
}

func iffall(o: E): A {
  let out = A::new(-1);
  if let E::V(s) = o {
    out = s;
  }
  return out;
}

func main(){
  //return-escape: payload moves out, scrutinee must not drop.
  reset();
  let a = iftake(E::V{v: A::new(1)});
  check_ids();
  send(a);
  check_ids(1);

  //non-matching: scrutinee intact, drops normally.
  reset();
  let b = iftake(E::W);
  check_ids();
  send(b);
  check_ids(99);

  //fallthrough with move to outer var (assign shape).
  reset();
  let c = iffall(E::V{v: A::new(2)});
  check_ids(-1);
  reset();
  send(c);
  check_ids(2);

  //inspect-only: binding copy drops in-arm, scrutinee leaks (no double).
  reset();
  {
    let e = E::V{v: A::new(3)};
    if let E::V(s) = e {
      assert(s.a == 3);
    }
  }
  check_ids(3);

  print("iflet done\n");
}
