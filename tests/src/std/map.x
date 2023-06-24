//import std/List
//import std/Option
import std/ops

class Pair<T, U>{
  a: T;
  b: U;
}

class Map<K, V>{
  arr: List<Pair<K, V>>;
}

impl<K, V> Map<K, V>{
  func new(): Map<K, V>{
    return Map<K, V>{List<Pair<K, V>>::new(100)};
  }
  
  func new(cap: i64): Map<K, V>{
    return Map<K, V>{List<Pair<K, V>>::new(cap)};
  }
  
  func len(self): i64{ return self.arr.len(); }
  
  func add(self, k: K, v: V){
    let p = Pair{k, v};
    self.arr.add(p);
  }
  
  func get(self, k: K): Option<V>{
    for(let i = 0;i < self.arr.len();i += 1){
      let e =  self.arr.get(i);
      if(Eq::eq(e.a, k)){
        return Option<V>::Some{e.b};
      }
    }
    return Option<V>::None;
  }
  func get(self, k: K*): Option<V>{
    return self.get(*k);
  }
  func get_idx(self, idx: i32): Option<Pair<K, V>*>{
    if(idx < self.len()){
      return Option::new(self.arr.get_ptr(idx));
    }
    return Option<Pair<K, V>*>::None;
  }
}

