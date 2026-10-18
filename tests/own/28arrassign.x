import own/common

//`arr[i] = v` used to overwrite the element without dropping the old value
//(a leak): `drop_lhs` only knew how to drop a struct field, so an index
//place fell through as an untracked expression. The aggregate keeps owning
//every element (a move out of an index place is refused, see Own::do_move),
//so the overwritten value is live and must drop at the assignment. The
//element address is what `store` hands to `drop_lhs`. This covers a field
//chain rooted at an index too (`h[0].a = v`, `m[0][1] = v`), which arrives
//as an untracked expression because its base has no vh.

struct Holder{
  a: A;
  n: i32;
}

func case_assign(){
  let a = [A::new(1), A::new(2)];
  a[0] = A::new(9);      //drops the old element 1
  check_ids(1);
  reset();
  a[1] = A::new(8);      //drops the old element 2
  check_ids(2);
  reset();
  //a drops here: 9 then 8
}

func case_field_of_element(){
  let h = [Holder{a: A::new(30), n: 1}, Holder{a: A::new(31), n: 2}];
  h[0].a = A::new(40);   //drops the old 30
  check_ids(30);
  reset();
  //h drops here: 40 then 31
}

func case_nested(){
  let m = [[A::new(50), A::new(51)], [A::new(52), A::new(53)]];
  m[0][1] = A::new(54);  //drops the old 51
  check_ids(51);
  reset();
  //m drops here: 50 54 52 53
}

func main(){
  case_assign();
  check_ids(9, 8);
  reset();

  case_field_of_element();
  check_ids(40, 31);
  reset();

  case_nested();
  assert_eq(ids.len(), 4);
  assert_eq(*ids.peek_front(0), 50);
  assert_eq(*ids.peek_front(1), 54);
  assert_eq(*ids.peek_front(2), 52);
  assert_eq(*ids.peek_front(3), 53);
  reset();

  print("arrassign done\n");
}
