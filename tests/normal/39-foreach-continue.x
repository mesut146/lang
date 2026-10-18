import std/it

//`continue` in a for-each whose body also ends in a `return` used to fail
//codegen: the for-each desugar ends its `while(true)` body with the opaque
//`std::internal_block!(id)`, which Exit::get_exit_type reads as NONE, so the
//loop could not see the trailing terminator and appended its back-edge after
//the already-terminated block ("Terminator found in the middle of a basic
//block"). See Emitter::body_exit in src/backend/stmt_emitter.x.

func main(){
  let a = [1, 2, 3];
  let items = a[0..3];

  //continue, loop runs to completion (back-edge still emitted)
  let seen = 0;
  for x in &items{
    if(*x == 2){
      continue;
    }
    seen = seen + *x;
  }
  assert(seen == 4);

  //continue with a trailing return: the body ends in a terminator
  for y in &items{
    if(*y % 2 == 0){
      continue;
    }
    assert(*y == 1);
    print("foreach continue done\n");
    return;
  }
  assert(false);
}
