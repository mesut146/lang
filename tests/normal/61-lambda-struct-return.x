//A lambda whose return type is a struct must use the same ABI as the method the
//compiler generates for it: a struct result is written through a hidden
//destination pointer (arg 0) and the call itself returns void. The call site
//used to take the lambda's prototype at face value (struct returned by value),
//so `let f = |x: i32|: P{ ... }; f(1)` read the void result as the struct and
//segfaulted. Covered: plain, capturing, via a generic function (opaque T),
//through a function pointer, and with an owning (String) field so the
//temporary is allocated, moved out and dropped exactly once.
import std/io
import std/string

struct P{
  a: i32;
  b: i32;
}

struct Named{
  name: String;
  n: i32;
}

func mk(x: i32): P{
  return P{a: x, b: x + 1};
}

func apply<T>(fp: T, x: i32): P{
  return fp(x);
}

func main(){
  let f = |x: i32|: P{
    return P{a: x, b: x * 2};
  };
  let p = f(21);
  assert(p.a == 21);
  assert(p.b == 42);

  //captured values are extra arguments after the sret pointer
  let base = 40;
  let g = |x: i32|: P{
    return P{a: base + x, b: base - x};
  };
  let q = g(2);
  assert(q.a == 42);
  assert(q.b == 38);

  //through a generic function: the lambda is an opaque T there
  let r = apply(f, 10);
  assert(r.a == 10);
  assert(r.b == 20);

  //owning field: the result is a real temporary that must be dropped once
  let h = |x: i32|: Named{
    return Named{name: String::new("hello"), n: x};
  };
  let s = h(7);
  assert(s.n == 7);
  assert(s.name.eq("hello"));

  //function pointer to a struct-returning function
  let fp: func(i32) => P = mk;
  let t = fp(41);
  assert(t.a == 41);
  assert(t.b == 42);

  //in a loop: every iteration allocates and drops its own result
  let sum = 0;
  for(let i = 0;i < 100;++i){
    let v = f(i);
    sum = sum + v.b;
  }
  assert(sum == 9900);
  print("lambda struct return done\n");
}
