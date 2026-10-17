import std/box

//Box<T>::drop delegates to `Drop::drop(self.unwrap())`; unwrap frees the
//malloc'd cell. When the payload has no drop glue the emitter used to
//elide the whole `Drop::drop(arg)` call - argument included - so unwrap
//never ran and every such cell leaked. Raw malloc leak, invisible to the
//drop-count tracker (see bin/test.sh leak).
struct Plain{
  v: i32;
}

func boxed_prim(){
  let b = Box<i32>::new(42);
  assert(*b.get() == 42);
}

func boxed_plain(){
  let b = Box<Plain>::new(Plain{v: 7});
  assert(b.get().v == 7);
}

func main(){
  boxed_prim();
  boxed_plain();
  print("box_nondrop done\n");
}
