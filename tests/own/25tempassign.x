import own/common

//A field of a call-result temporary is an owned place: the engine registers
//the temporary as an object (and drops it at scope end), so assigning to one
//of its drop-typed fields must drop the overwritten value. `f().field = v`
//used to leak the old value silently (drop_lhs bailed: the base has no vh
//and is not a registered name).

struct Inner{
  v: A;
}
struct Outer{
  p: Inner;
}

func mk_inner(id: i32): Inner{
  return Inner{v: A::new(id)};
}
func mk_outer(id: i32): Outer{
  return Outer{p: Inner{v: A::new(id)}};
}

//direct field of a call result
func case_temp_field(){
  reset();
  mk_inner(80).v = A::new(81);
  check_ids(80);      //old field value dropped at the assign (leaked pre-fix)
  //the temporary drops here -> A{81}
}

//nested field of a call result: still one owned temporary
func case_temp_field_nested(){
  reset();
  mk_outer(82).p.v = A::new(83);
  check_ids(82);      //old value dropped (leaked pre-fix)
  //the temporary drops here -> A{83}
}

func main(){
  case_temp_field();
  case_temp_field_nested();
  print("tempassign done\n");
}
