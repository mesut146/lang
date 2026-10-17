import own/common
import std/th

//A worker job arg is boxed in an Any. Auto-drop is type-erased, so the boxed
//payload's innards are freed only if the runner is handed T's drop glue
//(Worker::add_arg_heap, backed by Any::new<T>(val, glue)). With the glue-less
//add_arg<T>, A::drop never runs and the tracker count stays 0.
func drop_a(p: i8*){
  let a: A = ptr::deref!(p as A*);
  Drop::drop(a);
}

func job(arg: c_void*){
  let a = arg as A*;
  a.check(1);
}

func main(){
  reset();
  let worker = Worker::new(1);
  worker.add_arg_heap(job, A::new(1), drop_a);
  worker.join();
  check_ids(1);
}
