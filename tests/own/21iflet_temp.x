import own/common

//if-let over an owned temporary whose runtime variant does NOT match the
//pattern: nothing is copied out, so the temporary must drop on the else
//path. Used to leak (the scrutinee temp was marked moved for the match
//path and nothing dropped it when the match failed).
enum E{
  V{v: A},
  W
}

func get(b: bool): E{
  if(b){
    return E::V{v: A::new(21)};
  }
  return E::W;
}

func nomatch(){
  if let E::W = get(true){
    print("W\n");
  }
}

func main(){
  reset();
  nomatch();
  //the non-matching temporary's A must have dropped exactly once
  check_ids(21);
  print("iflet_temp done\n");
}
