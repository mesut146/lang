import own/common

//An array or tuple owns its elements. Dropping such a value used to crash the
//compiler in Emitter::drop_force (get_drop_proto does get_decl(rt).unwrap(),
//None for a decl-less type -> "unwrap on None", option.x:26), and the element
//sources of a literal were never marked moved, so they would have been
//dropped a second time. Reported as: `let x = [String::new("a"), ..]` panics
//the compiler.
//
//Here the sources are marked moved (do_move, like struct fields), the value
//drops element-wise in order, and a partial move follows the struct rule
//(every drop-typed element must be moved).

func case_array_literal(){
  let arr = [A::new(90), A::new(91)];
  assert(arr.len() == 2);
  //arr drops element-wise here: 90 then 91
}

func case_array_of_struct(){
  let arr = [B::new(92), B::new(93)];
  //B::drop each element here: 92 then 93
}

func case_nested_array(){
  let arr = [[A::new(94)], [A::new(95)]];
  //94 then 95
}

func case_tuple(){
  let t = (A::new(96), 7, A::new(97));
  assert(t.1 == 7);
  //96 then 97
}

func take_arr(a: [A; 2]){
  //the callee owns its copy: drops 98 then 99 there
}

func case_pass_whole(){
  let arr = [A::new(98), A::new(99)];
  take_arr(arr);
  //arr was moved into take_arr
}

func case_tuple_partial(){
  let t = (A::new(100), A::new(101));
  send(t.0);
  send(t.1);
  //every drop element moved: nothing drops at scope end
}

func main(){
  reset(); case_array_literal(); check_ids(90, 91);
  reset(); case_array_of_struct(); check_ids(92, 93);
  reset(); case_nested_array(); check_ids(94, 95);
  reset(); case_tuple(); check_ids(96, 97);
  reset(); case_pass_whole(); check_ids(98, 99);
  reset(); case_tuple_partial(); check_ids(100, 101);
  print("arrtuple done\n");
}
