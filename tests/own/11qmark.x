import own/common
import std/result

//?-with-drop-payload on the Ok path: the scrutinee temp must not drop
//the payload the Ok binding moved out (used to double-free / segfault).
func maybe(ok: bool): Result<A, str>{
  if(ok){
    return Result<A, str>::Ok{A::new(10)};
  }
  return Result<A, str>::Err{"no"};
}

func useit(): Result<A, str>{
  let r = maybe(true)?;
  return Result<A, str>::Ok{r};
}

func useit_err(): Result<A, str>{
  let r = maybe(false)?;
  return Result<A, str>::Ok{r};
}

func main(){
  let a = useit();
  let x = a.unwrap();
  x.check(10);
  reset();
  send(x);
  check_ids(10);
  //Err path: returns early, nothing owned by A drops here
  let e = useit_err();
  assert(e.is_err());
  print("qmark done\n");
}
