import own/common

struct N{
  v: A;
  next: Option<A>;
}

//take() moves the value out leaving None: the old place drops nothing,
//so unlike moving a field out of a temporary this never double-drops.
//Infallible: None in gives None out.
func main(){
  let o = Option<A>::new(A::new(10));
  let x = o.take().unwrap();
  x.check(10);
  assert(o.is_none());
  reset();
  send(x);
  check_ids(10);

  //None passes through
  reset();
  let n = Option<A>::none();
  let m = n.take();
  assert(m.is_none());
  check_ids();

  //take through a field: the llist::remove pattern made sound
  let p = N{v: A::new(1), next: Option<A>::new(A::new(2))};
  let t = p.next.take().unwrap();
  t.check(2);
  assert(p.next.is_none());
  reset();
  send(t);
  check_ids(2);
  //p drops only v here (next is None)
  print("take done\n");
}
