//Printing a `String` must not deep-copy it. `Fmt::print` had only a by-value
//`String` overload, so `f.print(&field)` (what every Debug impl writes) bound
//to the generic `print<T>(node: T*)` -> `Debug::debug(node, ..)`, and that
//takes `self: String` by value -- i.e. the field was cloned just to print it.
//`Fmt::str` had the same shape in reverse: it returned `f.buf.clone()`, a full
//copy of everything it had just built. Both sit on the type-mangling path
//(`Type::print()` is `Fmt::str(self)`), 89k String copies per 25-file compile,
//so `Fmt::str` now moves its buffer out (`unwrap`) and `print` has a
//`String*` overload. This pins the text both paths produce.
import std/io
import std/string

#derive(Debug)
struct Named{
  name: String;
  n: i32;
}

func main(){
  let s = String::new("hi");
  //by-value String path (`print(String)`)
  assert(format("{}", s).eq("hi"));
  //derived Debug prints the String *field*, i.e. `f.print(&self.name)`:
  //this is the pointer overload, and the text must be the bytes, not quotes
  let nm = Named{name: s.clone(), n: 7};
  let d = format("{:?}", nm);
  assert(d.eq("Named{name: hi, n: 7}"));
  //the empty String has a null buffer: appending it through either overload
  //must be a no-op, not a dereference
  let e = String::new();
  assert(format("{}", e).eq(""));
  assert(format("{}x", e).eq("x"));
  assert(format("{:?}", Named{name: e, n: 0}).eq("Named{name: , n: 0}"));
  print("fmt string print ok\n");
}
