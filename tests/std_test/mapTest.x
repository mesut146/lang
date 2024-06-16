import std/map
import std/ops
import std/libc

enum En{
  A,
  B(a: i32)
}

func main(){
  let m = Map<i32, i32>::new();
  m.add(2, 4);
  m.add(7, 49);
  assert(*m.get_ptr(&2).unwrap() == 4);
  assert(*m.get_ptr(&7).unwrap() == 49);
  m.drop();
  
  let m2 = Map<i32, Pair<i32, i32>>::new();
  m2.add(3, Pair{4, 5});
  m2.add(5, Pair{12, 13});
  let p1 = m2.get_ptr(&3).unwrap();
  assert(p1.a == 4 && p1.b == 5);
  let p2 = m2.get_ptr(&5).unwrap();
  assert(p2.a == 12);
  m2.drop();
  
  let m3 = Map<i32, En>::new();
  m3.add(5, En::A);
  m3.add(7, En::B{77});
  assert(m3.get_ptr(&5).unwrap() is En::A);
  assert(m3.get_ptr(&7).unwrap() is En::B);
  m3.drop();
  
  print("map_test done\n");
}