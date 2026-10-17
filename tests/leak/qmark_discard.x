import std/result

//discarded `?` payload: the moved-out String buffer must be freed. Raw
//malloc leak, invisible to the drop-count tracker (see bin/test.sh leak).
func maybe(ok: bool): Result<String, str>{
  if(ok){
    return Result<String, str>::Ok{String::new("payload")};
  }
  return Result<String, str>::Err{"no"};
}

func discarded(): Result<i32, str>{
  maybe(true)?;
  return Result<i32, str>::Ok{0};
}

func main(){
  let r = discarded();
  assert(r.is_ok());
  print("qmark_discard done\n");
}
