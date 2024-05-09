//import std/List
//import std/Option
import std/ops

struct Pair<T, U>{
  a: T;
  b: U;
}

impl<K, V> Pair<K, V>{
  func new(a: K, b: V): Pair<K, V>{
    return Pair{a, b};
  }
}

impl<A,B> Debug for Pair<A,B>{
  func debug(self, f: Fmt*){
    f.print("{");
    Debug::debug(&self.a, f);
    f.print(", ");
    Debug::debug(&self.b, f);
    f.print("}");
  }
}

struct Map<K, V>{
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
  func empty(self): bool{ return self.arr.empty(); }
  
  func add(self, k: K, v: V): Pair<K, V>*{
    let i = self.indexOf(&k);
    //doesnt exist, add last
    if(i == -1_i64){
      let p = Pair{k, v};
      self.arr.add(p);
      return self.arr.last();
    }
    else{
      //already exist, change old
      let p = self.arr.get_ptr(i);
      Drop::drop(p.b);
      p.b = v;
      return p;
    }
  }

  func contains(self, k: K*): bool{
    return self.indexOf(k) != -1;
  }
  
  func get(self, k: K): Option<V*>{
    return self.get_ptr(&k);
  }
  /*func get_p(self, k: K*): Option<V>{
    for(let i = 0;i < self.arr.len();i += 1){
      let ptr =  self.arr.get_ptr(i);
      if(Eq::eq(&e.a, k)){
        return Option<V>::Some{pr.b};
      }
    }
    return Option<V>::None;
  }*/
  func get_ptr(self, k: K*): Option<V*>{
    for(let i = 0;i < self.arr.len();i += 1){
      let e =  self.arr.get_ptr(i);
      if(Eq::eq(&e.a, k)){
        return Option<V*>::Some{&e.b};
      }
    }
    return Option<V*>::None;
  }  
  func indexOf(self, k: K*): i64{
    for(let i = 0;i < self.arr.len();i += 1){
      let pr =  self.arr.get_ptr(i);
      if(Eq::eq(&pr.a, k)){
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

  func clear(self){
    self.arr.clear();
  }
}