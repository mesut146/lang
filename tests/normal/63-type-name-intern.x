//`Simple.name` is a slice into an interned name pool, not an owned String: a
//type copy used to clone the name, and that was a third of the compiler's
//String::clone traffic (228k copies of 4-byte names in a 25-file compile).
//The pool has to hand out one distinct, stable slice per name for the whole
//compilation. A dangling or aliasing slice would merge two types' mangled
//symbols, and one instantiation's method body would then answer for another,
//so this pins the paths that read a type name back: generic instantiation and
//mangling, generic functions, enum variant lookup, module scopes and derives.
import std/io
import std/string

struct Slot<T>{
  val: T;
}
impl<T> Slot<T>{
  func get(self): T{
    return self.val;
  }
}

enum Shape{
  Dot,
  Line,
}

func name_of(s: Shape): String{
  match s{
    Shape::Dot => return "dot".owned(),
    Shape::Line => return "line".owned(),
  }
}

#derive(Debug)
struct Named{
  name: String;
  n: i32;
}

func id<T>(v: T): T{
  return v;
}

func main(){
  //one instantiation per element type: distinct mangled names, distinct bodies
  let a = Slot<i8>{val: 7 as i8};
  let b = Slot<i32>{val: 70000};
  let c = Slot<i64>{val: 5 as i64};
  let d = Slot<u8>{val: 200 as u8};
  let e = Slot<f64>{val: 1.5};
  let f = Slot<bool>{val: true};
  let st = "s".owned();
  let g = Slot<String*>{val: &st};
  let p = &b.val;
  let h = Slot<i32*>{val: p};
  assert(a.get() == 7);
  assert(b.get() == 70000);
  assert(c.get() == 5);
  assert(d.get() == 200);
  assert(e.get() == 1.5);
  assert(f.get());
  assert(g.get().eq("s"));
  assert(*h.get() == 70000);
  //a generic function over the same names, plus nested instantiations
  assert(id<i32>(5) == 5);
  assert(id<i8>(5 as i8) == 5);
  assert(id<Slot<i32>>(b).get() == 70000);
  //enum variants are looked up by name (findVariant)
  assert(name_of(Shape::Dot).eq("dot"));
  assert(name_of(Shape::Line).eq("line"));
  //derives re-print the declaring type's name when they copy variant/field types
  let n = Named{name: "hi".owned(), n: 1};
  assert(format("{:?}", n).eq("Named{name: hi, n: 1}"));
  print("type name intern ok\n");
}
