import own/common
import std/result

//discarded `?` payload: the Ok value moves out of the scrutinee with no
//binding to own it, so statement-position `?` must drop it. Used to leak
//(the payload temp was never registered with the ownership engine, unlike
//a normal struct-returning call).
func maybe(ok: bool): Result<A, str>{
  if(ok){
    return Result<A, str>::Ok{A::new(20)};
  }
  return Result<A, str>::Err{"no"};
}

func discarded(): Result<i32, str>{
  maybe(true)?;
  return Result<i32, str>::Ok{0};
}

func main(){
  reset();
  let r = discarded();
  assert(r.is_ok());
  //the discarded A must have dropped exactly once
  check_ids(20);
  print("qmark_discard done\n");
}
