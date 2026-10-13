import own/common

struct Holder{
  v: A;
  n: i32;
}
func take_a(x: A){
}

//drop-on-assign: every overwritten live value drops in place, exactly
//once, in order (see Own::drop_lhs). Pins struct, enum, field, deref
//and manual-then-reassign shapes.
func main(){
  //plain var reassign
  let a = A::new(1);
  a = A::new(2);
  check_ids(1);
  a = A::new(3);
  check_ids(1, 2);
  reset();
  send(a);
  check_ids(3);

  //struct-literal rhs (inline path) also drops the old value
  reset();
  let i = A::new(10);
  i = A{a: 11};
  check_ids(10);
  reset();
  send(i);
  check_ids(11);

  //enum reassign
  reset();
  let o = Option<A>::new(A::new(20));
  o = Option<A>::new(A::new(21));
  check_ids(20);
  reset();
  send(o.unwrap());
  check_ids(21);

  //field reassign drops the old field value
  reset();
  let h = Holder{v: A::new(4), n: 0};
  h.v = A::new(5);
  check_ids(4);

  //heal-after-move still skips the drop (moved-out, not live)
  take_a(h.v);
  h.v = A::new(6);
  check_ids(4, 5);

  //deref reassign over live data drops the old value
  reset();
  let b = A::new(7);
  let pb = &b;
  *pb = A::new(8);
  check_ids(7);

  //deref heal-after-move: the heap died once in the callee; the heal
  //overwrites the dangling source without dropping (no double)
  reset();
  let c = A::new(30);
  let pc = &c;
  send(*pc);
  check_ids(30);
  *pc = A::new(31);
  check_ids(30);
  reset();
  send(c);
  check_ids(31);

  //manual drop then reassign: still exactly once, no double
  reset();
  let m = A::new(40);
  m.drop();
  m = A::new(41);
  reset();
  send(m);
  check_ids(41);

  print("reassign done\n");
}
