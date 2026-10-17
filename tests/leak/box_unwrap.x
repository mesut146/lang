import std/box

//Box::unwrap on a named box: the payload moves to the caller but the
//malloc'd box cell must be freed. Raw malloc leak, invisible to the
//drop-count tracker (see bin/test.sh leak).
struct A{
  v: i32;
}
impl Drop for A{
  func drop(*self){
  }
}

func main(){
  let b = Box<A>::new(A{v: 1});
  let a = b.unwrap();
  assert(a.v == 1);
  print("box_unwrap done\n");
}
