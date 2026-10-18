import own/common
import std/map
import std/option

//The manual `Drop::drop(old)` + `std::no_drop(place)` pairs that used to
//hand-drop the overwritten value are gone: auto-drop (drop-on-assign) now
//owns every in-place overwrite. This pins the exact shapes that were
//removed, so a regression shows up as a short count (leak) or an extra
//drop (double free):
//  - pointer field assign          `p.f = x`   (Map::add pair.a/pair.b)
//  - pointer whole-place assign    `*p = x`    (Option::set/reset)
//  - unused owned arg on a hit                 (Map::get_pair_or)
//  - unsafe deref member place     `ptr::deref!(p).f`  (assign + move/heal)

struct Holder{
  v: A;
}

//pointer field assign: the old value must drop in place, exactly once
func set_ptr(h: Holder*, id: i32){
  h.v = A::new(id);
}

//pointer whole-place assign, live old value (the Option::set shape)
func set_deref(o: Option<A>*, id: i32){
  *o = Option::new(A::new(id));
}

//pointer whole-place assign, clearing (the Option::reset shape)
func clear(o: Option<A>*){
  *o = Option<A>::new();
}

//unsafe deref member assign: `ptr::deref!(p).f` names the same place as
//`p.f`, so the overwritten value must drop (this shape used to leak)
func set_deref_macro(h: Holder*, id: i32){
  ptr::deref!(h).v = A::new(id);
}

func case_field(){
  reset();
  let h = Holder{v: A::new(1)};
  set_ptr(&h, 2);
  check_ids(1);       //old field value dropped
  //h drops here -> A{2}
}

func case_deref(){
  reset();
  let o = Option::new(A::new(10));
  set_deref(&o, 11);
  check_ids(10);      //old Some payload dropped
  assert(o.get().a == 11);   //new value is live
  //o drops here -> A{11}
}

func case_reset(){
  reset();
  let r = Option::new(A::new(20));
  clear(&r);
  check_ids(20);      //held value dropped, now None
  assert(r.is_none());
}

func case_deref_macro(){
  reset();
  let h = Holder{v: A::new(60)};
  set_deref_macro(&h, 61);
  check_ids(60);      //old field value dropped (leaked before the fix)
  assert(h.v.a == 61);
  //h drops here -> A{61}
}

func case_deref_macro_move(){
  reset();
  let h = Holder{v: A::new(70)};
  let hp = &h;
  let old = ptr::deref!(hp).v;   //move out: tracked as h.v now
  check_ids();                   //nothing dropped yet
  ptr::deref!(hp).v = A::new(71);//same place: the heal
  check_ids();                   //heal assign drops nothing (no double)
  send(old);
  check_ids(70);
  //h drops here -> A{71}
}

func case_map_add(){
  reset();
  let m = Map<i32, A>::new();
  m.add(1, A::new(30));
  m.add(1, A::new(31));   //same key: overwritten value drops
  check_ids(30);
  m.get(&1).unwrap().check(31);
  //m drops here -> A{31}
}

func case_pair_or(){
  reset();
  let m = Map<i32, A>::new();
  m.add(1, A::new(50));
  reset();
  let p = m.get_pair_or(1, A::new(51));   //hit: unused def drops
  check_ids(51);
  p.b.check(50);
  //m drops here -> A{50}
}

func main(){
  case_field();
  case_deref();
  case_reset();
  case_deref_macro();
  case_deref_macro_move();
  case_map_add();
  case_pair_or();
  print("ptrassign done\n");
}
