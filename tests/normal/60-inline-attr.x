//`#[inline]` is a hint the compiler honours even when the build does no other
//optimization: the emitter marks the definition alwaysinline and the no--O
//pipeline runs LLVM's always-inliner. It must not change semantics, and it has
//to work for plain functions, generic functions and methods alike (the last
//two go through the instantiation path, which copies the attribute).
import std/io

#[inline]
func twice(x: i64): i64{
  return x * 2;
}

#[inline]
func pick<T>(a: T, b: T, first: bool): T{
  if(first){
    return a;
  }
  return b;
}

struct Pair{
  a: i64;
  b: i64;
}

impl Pair{
  #[inline]
  func sum(self): i64{
    return self.a + self.b;
  }
}

func main(){
  assert(twice(21) == 42);
  assert(twice(-3) == -6);
  assert(pick(1, 2, true) == 1);
  assert(pick(1, 2, false) == 2);
  assert(pick("x", "y", true).eq("x"));
  let p = Pair{a: 40, b: 2};
  assert(p.sum() == 42);
  //and the same through a loop, where the inlined body is exercised
  let acc = 0i64;
  for(let i = 0;i < 1000;++i){
    acc = acc + twice(i as i64);
  }
  assert(acc == 999000);
  print("inline attr done\n");
}
