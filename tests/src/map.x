import List
import Option
import ops

class Pair<T, U>{
  a: T;
  b: U;
}

class Map<K, V>{
  arr: List<Pair<K, V>>;
}

impl Map<K, V>{
  func new(): Map<K, V>{
    return Map<K, V>{List<Pair<K, V>>::new(100)};
  }
  
  func new(cap: i64): Map<K, V>{
    return Map<K, V>{List<Pair<K, V>>::new(cap)};
  }
  
  func len(self): i32{ return self.arr.len(); }
  
  func add(self, k: K, v: V){
    let p = Pair{k, v};
    self.arr.add(p);
  }
  
  func get(self, k: K): Option<V>{
    for(let i = 0;i < self.arr.len();i += 1){
      let e =  self.arr.get(i);
      if(e.a.eq(k)){
        return Option<V>::Some{e.b};
      }
    }
    return Option<V>::None;
  }
}

enum En{
  A,
  B(a: i32)
}

func map_test(){
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