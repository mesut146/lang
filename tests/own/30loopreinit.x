import own/common

//A whole-var write reinitializes every field of that var, so the move marks
//its fields carry from before the write are stale (Own::note_reinit /
//reinit_places). This is std/hashmap's rehash loop: move the payload out,
//then reassign the whole loop variable from the next link. The stale mark
//must not read as a use after move, and the exit state must still name the
//moved fields -- if the marks were *deleted* instead, the var would look
//fully live and be dropped whole at scope end (double free; the old value's
//bytes already left). The post-loop use is the other half: the last
//iteration ended with the reinit, so it is live and must compile.

struct N{
  v: A;
  n: i32;
}

func take(x: A){
}

func make(id: i32): N{
  return N{A::new(id), 0};
}

func loop_reinit(){
  let x = make(1);
  let i = 0;
  while(i < 2){
    take(x.v);          //1, then 10
    x = make(10 + i);   //whole reinit: v is live again
    i += 1;
  }
  take(x.v);            //11 (live: the last iteration reassigned x)
  //x fully consumed here: nothing drops
}

func straight_reinit(){
  let x = make(20);
  take(x.v);            //20
  x = make(21);         //whole reinit covers v
  take(x.v);            //21 is live
  //x fully consumed here
}

func main(){
  loop_reinit();
  check_ids(1, 10, 11);
  reset();

  straight_reinit();
  check_ids(20, 21);
  reset();

  print("loopreinit done\n");
}
