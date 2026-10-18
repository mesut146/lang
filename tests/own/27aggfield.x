import own/common

//An aggregate *field* of a drop element type: derive.x emits
//`Drop::drop(self.f)` for it (is_struct is true for arrays/tuples), which
//used to fail to resolve -- "get_impl type not covered: [String; 2]".
//An array/tuple has no decl and hence no Drop impl; the call now drops the
//field's elements in place (the resolver skips impl resolution for
//aggregate arguments and the emitter calls drop_force).
//
//Covers a struct array field, a tuple field, a nested array field and an
//enum variant field. The enum case binds the payload to a local inside the
//generated drop, which the engine auto-drops at arm end, so the argument of
//`Drop::drop(v)` has to count as consumed (own_visitor) or it drops twice.

struct ArrS{
  a: [A; 2];
}

struct TupS{
  t: (A, A, i32);
}

struct NestedS{
  a: [[A; 2]; 2];
}

enum ES{
  Two{v: [A; 2]},
  One{s: A}
}

func case_struct_arr_field(){
  let s = ArrS{a: [A::new(10), A::new(11)]};
  assert(s.a.len() == 2);
  //s drops here: 10 then 11
}

func case_tuple_field(){
  let s = TupS{t: (A::new(12), A::new(13), 7)};
  assert(s.t.2 == 7);
  //12 then 13
}

func case_nested_field(){
  let s = NestedS{a: [[A::new(14), A::new(15)], [A::new(16), A::new(17)]]};
  //14 15 16 17
}

func case_enum_arr_field(){
  let e = ES::Two{v: [A::new(18), A::new(19)]};
  //18 then 19
}

func main(){
  reset(); case_struct_arr_field(); check_ids(10, 11);
  reset(); case_tuple_field(); check_ids(12, 13);
  reset(); case_nested_field();
  assert_eq(ids.len(), 4);
  assert_eq(*ids.peek_front(0), 14);
  assert_eq(*ids.peek_front(1), 15);
  assert_eq(*ids.peek_front(2), 16);
  assert_eq(*ids.peek_front(3), 17);
  reset(); case_enum_arr_field(); check_ids(18, 19);
  print("aggfield done\n");
}
