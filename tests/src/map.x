import List

class Pair<T, U>{
  a: T;
  b: U;
}

class Map<K, V>{
  arr: List<Pair<K, V>>;
}

impl Map<K, V>{
  func new(): Map<K, V>{
    return Map<K, V>{List<Pair<K, V>>::new(11)};
  }
  func add(self, k: K, v: V){
    let p = Pair{k, v};
    self.arr.add(p);
    let l = self.arr.get_ptr(self.arr.len() - 1);
    print("add %s=%d, %s=%d\n", k, v.index, l.a, l.b.index);
  }
  
  func get(self, k: K): Option<V>{
   print("len=%d\n", self.arr.len());
    for(let i = 0;i < self.arr.len();i += 1){
      let e =  self.arr.get(i);
      print("k=%s v=%d\n", e.a, e.b.index);
      if(e.a.eq(k)){
      print("idx=%d\n", e.b.index);
        return Option<V>::Some{e.b};
      }
    }
    return Option<V>::None;
  }
}