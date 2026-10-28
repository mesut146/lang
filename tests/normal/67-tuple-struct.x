// Positional (tuple) structs and empty enums.
//
// `struct T(i32, bool);` builds the field list with no names: construction is
// the unnamed-entry object form `T{1, true}`, fields are read and written by
// index (`t.0`), and the generated Clone/Drop/Debug/Display bodies walk the
// fields in declaration order. `enum Never {}` is an uninhabited type: it can
// be declared, used as a field/parameter type and derived on, but no value of
// it can ever be built.
//
// The owning field below pins that the *automatic* Drop impl for a tuple
// struct frees each positional field exactly once (hidden behind `Res::drop`'s
// counter); the Clone impl must clone the owned field and copy the plain one.

#derive(Debug, Clone, Display)
struct Pair(i32, i32);

//owned field: auto Drop + derived Clone must both understand positional slots
#drop
#derive(Clone)
struct Res{
  cnt: i32*;
}

impl Drop for Res{
  func drop(*self){
    *self.cnt += 1;
  }
}

#derive(Clone)
struct Holder(Res, i32);

//generic tuple struct: the positional entry infers the parameter
#derive(Debug, Clone)
struct Wrap<T>(T);

//zero positional fields
struct Empty();

//uninhabited: declared, used as a type, derived on
#derive(Debug, Clone, Display)
enum Never{}

struct Holds{
  n: Never;
  i: i32;
}

func sum(p: Pair): i32{
  return p.0 + p.1;
}

//`self.0` on an impl receiver (self is the declaration type)
impl Pair{
  func total(self): i32{
    return self.0 + self.1;
  }
}

//forces the empty enum into a parameter/field layout
func never(n: Never){
}

func touch(h: Holds){
  h.i = 0;
}

func drop_pair(cnt: i32*){
  let h = Holder{Res{cnt}, 2};
  assert(h.1 == 2);
  let h2 = h.clone();
  assert(h2.1 == 2);
}

func main(){
  let p = Pair{1, 2};
  assert(p.0 == 1 && p.1 == 2);
  assert(sum(p) == 3);
  //writable in place
  p.0 = 10;
  assert(p.0 == 10 && sum(p) == 12);
  //clone copies both slots
  let q = p.clone();
  assert(q.0 == 10 && q.1 == 2);
  q.1 = 20;
  assert(p.1 == 2);
  assert(format("{:?}", p).eq("Pair(10, 2)"));
  assert(format("{}", p).eq("Pair(10, 2)"));
  assert(p.total() == 12);

  let w = Wrap{5};
  assert(w.0 == 5);
  let w2 = w.clone();
  assert(w2.0 == 5);
  assert(format("{:?}", w2).eq("Wrap<i32>(5)"));
  let e = Empty{};
  assert(p.1 == 2);

  //two holders, two owned fields: the generated Drop runs each one once
  let cnt = 0;
  drop_pair(&cnt);
  assert(cnt == 2);
  print("tuple struct done\n");
}
