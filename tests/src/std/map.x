//import std/List
//import std/Option
import std/ops

class Pair<T, U>{
  a: T;
  b: U;
}

impl<K, V> Pair<K, V>{
  func new(a: K, b: V): Pair<K, V>{
    return Pair{a, b};
  }
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
  func size(self): i64{ return self.arr.len(); }
  func empty(self): bool{ return self.arr.empty(); }
  
  func add(self, k: K, v: V){
    let i = self.indexOf(&k);
    if(i == -1_i64){
      //print("map noset %d\n", i);
      let p = Pair{k, v};
      self.arr.add(p);
    }
    else{
      print("map set %d\n", i);
      let p = self.arr.get_ptr(i);
      print("map set from (%s,", Fmt::str2(p.a).cstr());
      print("%s) to (", Fmt::str2(p.b).cstr());
      print("%s,", Fmt::str(&k).cstr());
      print("%s)\n", Fmt::str2(v).cstr());
      p.b = v;
    }
  }

  func has(self, k: K*): bool{
    return self.indexOf(k) != -1;
  }
  
  func get(self, k: K): Option<V>{
    for(let i = 0;i < self.arr.len();i += 1){
      let e =  self.arr.get(i);
      if(Eq::eq(e.a, &k)){
        return Option<V>::Some{e.b};
      }
    }
    return Option<V>::None;
  }
  func get_p(self, k: K*): Option<V>{
    for(let i = 0;i < self.arr.len();i += 1){
      let e =  self.arr.get_ptr(i);
      if(Eq::eq(e.a, k)){
        return Option<V>::Some{e.b};
      }
    }
    return Option<V>::None;
  }
  func get_ptr(self, k: K*): Option<V*>{
    for(let i = 0;i < self.arr.len();i += 1){
      let e =  self.arr.get_ptr(i);
      if(Eq::eq(e.a, k)){
        return Option<V*>::Some{&e.b};
      }
    }
    return Option<V*>::None;
  }  
  func indexOf(self, k: K*): i64{
    for(let i = 0;i < self.arr.len();i += 1){
      let e =  self.arr.get_ptr(i);
      if(Eq::eq(e.a, k)){
        return i as i64;
      }
    }
    return -1 as i64;
  }
  func get_idx(self, idx: i32): Option<Pair<K, V>*>{
    if(idx < self.len()){
      return Option::new(self.arr.get_ptr(idx));
    }
    return Option<Pair<K, V>*>::None;
  }

  func remove(self, idx: i64){
    self.arr.remove(idx);
  }
}

