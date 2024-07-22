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

struct Map<K, V>{
  arr: List<Pair<K, V>>;
}

impl<K, V> Map<K, V>{
  func new(): Map<K, V>{
    return Map<K, V>{List<Pair<K, V>>::new()};
  }
  
  func new(cap: i64): Map<K, V>{
    return Map<K, V>{List<Pair<K, V>>::new(cap)};
  }
  
  func len(self): i64{ return self.arr.len(); }

  func empty(self): bool{ return self.arr.empty(); }
  
  func add(self, k: K, v: V): Pair<K, V>*{
    let opt = self.get_pair(&k);
    //doesnt exist, add last
    if(opt.is_none()){
      let res = self.arr.add(Pair{k, v});
      return res;
    }
    //already exist, change old
    let pair: Pair<K, V>* = opt.unwrap();
    let old_b = ptr::deref(&pair.b);
    Drop::drop(old_b);

    let old_a = ptr::deref(&pair.a);
    Drop::drop(old_a);

    pair.a = k;//todo add option to keep old key
    pair.b = v;
    return pair;
  }

  func contains(self, k: K*): bool{
    return self.indexOf(k) != -1;
  }

  func get_ptr(self, k: K*): Option<V*>{
    let opt = self.get_pair(k);
    if(opt.is_some()){
      return Option<V*>::Some{&opt.unwrap().b};
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
  func get_pair(self, k: K*): Option<Pair<K, V>*>{
    for(let i = 0;i < self.arr.len();++i){
      let pr =  self.arr.get_ptr(i);
      if(Eq::eq(&pr.a, k)){
        return Option::new(pr);
      }
    }
    return Option<Pair<K, V>*>::None;
  }
  func get_pair_idx(self, idx: i32): Option<Pair<K, V>*>{
    if(idx < self.len()){
      return Option::new(self.arr.get_ptr(idx));
    }
    return Option<Pair<K, V>*>::None;
  }

  func get_idx(self, idx: i32): V*{
    return &self.get_pair_idx(idx).unwrap().b;
  }

  func remove_idx(self, idx: i64): Pair<K, V>{
    let tmp = self.arr.remove(idx);
    return tmp;
  }

  func remove(self, k: K*){
    let idx = self.indexOf(k);
    if(idx != -1){
      let old = self.remove_idx(idx);
      old.drop();
    }
  }

  func clear(self){
    self.arr.clear();
  }
}

impl<K, V> Debug for Map<K, V>{
  func debug(self, f: Fmt*){
    f.print("{");
    for(let i = 0;i < self.len();++i){
      if(i > 0){
        f.print(", ");
      }
      Debug::debug(self.arr.get_ptr(i), f);
    }
    f.print("}");
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
impl<K,V> Clone for Map<K,V>{
  func clone(self): Map<K, V>{
    return Map<K, V>{self.arr.clone()};
  }
}
impl<K,V> Clone for Pair<K,V>{
  func clone(self): Pair<K, V>{
    return Pair<K, V>{self.a.clone(), self.b.clone()};
  }
}