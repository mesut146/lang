import std/map

enum En{
  A,
  B(a: i32)
}

func main(){
  let m = Map<i32, i32>::new();
  m.add(2, 4);
  m.add(7, 49);
  assert m.get(2).unwrap() == 4;
  assert m.get(7).unwrap() == 49;
  
  let m2 = Map<i32, Pair<i32, i32>>::new();
  m2.add(3, Pair{4, 5});
  m2.add(5, Pair{12, 13});
  let p1 = m2.get(3).unwrap();
  assert p1.a == 4 && p1.b == 5;
  let p2 = m2.get(5).unwrap();
  assert p2.a == 12;
  
  let m3 = Map<i32, En>::new();
  m3.add(5, En::A);
  m3.add(7, En::B{77});
  assert m3.get(5).unwrap().index == 0;
  assert m3.get(7).unwrap() is En::B;
  
  print("map_test done\n");
}