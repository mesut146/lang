//import std/List
//import std/Option
import std/ops

struct Pair<K, V>{
  a: K;
  b: V;
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
    let old_a = ptr::deref(&pair.a);
    let old_b = ptr::deref(&pair.b);
    Drop::drop(old_a);
    Drop::drop(old_b);
    std::no_drop(pair.a);
    std::no_drop(pair.b);

    pair.a = k;//todo add option to keep old key
    pair.b = v;
    return pair;
  }

  func contains(self, k: K*): bool{
    return self.indexOf(k) != -1;
  }

  func indexOf(self, k: K*): i64{
    for(let i = 0;i < self.arr.len();i += 1){
      let pr =  self.arr.get(i);
      if(Eq::eq(&pr.a, k)){
        return i as i64;
      }
    }
    return -1 as i64;
  }

  func get(self, k: K*): Option<V*>{
    let opt = self.get_pair(k);
    if(opt.is_some()){
      return Option<V*>::new(&opt.unwrap().b);
    }
    return Option<V*>::new();
  }

  func get_str(self, k: str): Option<V*>{
    let opt = self.get_pair_str(k);
    if(opt.is_some()){
      return Option<V*>::new(&opt.unwrap().b);
    }
    return Option<V*>::new();
  }

  func get_pair_str(self, key: str): Option<Pair<K, V>*>{
    for(let i = 0;i < self.arr.len();++i){
      let pair = self.arr.get(i);
      let s1: str = String::str(&pair.a);
      if(Eq::eq(s1, key)){
        return Option::new(pair);
      }
    }
    return Option<Pair<K, V>*>::new();
  }

  func get_pair(self, k: K*): Option<Pair<K, V>*>{
    for(let i = 0;i < self.arr.len();++i){
      let pair = self.arr.get(i);
      if(Eq::eq(&pair.a, k)){
        return Option::new(pair);
      }
    }
    return Option<Pair<K, V>*>::new();
  }
  func get_pair_or(self, key: K, def: V): Pair<K, V>*{
    for(let i = 0;i < self.arr.len();++i){
      let pair = self.arr.get(i);
      if(Eq::eq(&pair.a, &key)){
        Drop::drop(key);
        Drop::drop(def);
        return pair;
      }
    }
    return self.add(key, def);
  }
  func get_pair_idx(self, idx: i32): Option<Pair<K, V>*>{
    if(idx < self.len()){
      return Option::new(self.arr.get(idx));
    }
    return Option<Pair<K, V>*>::new();
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

  func iter(self): MapIter<K, V>{
    return MapIter{self, 0};
  }
  func into_iter(*self): MapIntoIter<K, V>{
    return MapIntoIter{self, 0};
  }
  func values(self): ValuesIter<K, V>{
    return ValuesIter{self, 0};
  }
}



impl<K, V> Debug for Map<K, V>{
  func debug(self, f: Fmt*){
    f.print("{");
    for(let i = 0;i < self.len();++i){
      if(i > 0){
        f.print(", ");
      }
      Debug::debug(self.arr.get(i), f);
    }
    f.print("}");
  }
}

impl<A, B> Debug for Pair<A, B>{
  func debug(self, f: Fmt*){
    f.print("{");
    debug_member!(self.a, f);
    //Debug::debug(&self.a, f);
    f.print(", ");
    //Debug::debug(&self.b, f);
    debug_member!(self.b, f);
    f.print("}");
  }
}
impl<K,V> Clone for Map<K,V>{
  func clone(self): Map<K, V>{
    return Map<K, V>{self.arr.clone()};
  }
}

//todo clone of ptr
impl<K,V> Clone for Pair<K,V>{
  func clone(self): Pair<K, V>{
    return Pair<K, V>{self.a.clone(), self.b.clone()};
  }
}

//iters
struct MapIter<K, V>{
  map: Map<K, V>*;
  pos: i32;
}
impl<K, V> Iterator<Pair<K*, V*>> for MapIter<K, V>{
  func next(self): Option<Pair<K*, V*>>{
    if(self.pos < self.map.len()){
      let idx = self.pos;
      self.pos += 1;
      let p = self.map.get_pair_idx(idx).unwrap();
      return Option::new(Pair::new(&p.a, &p.b));
    }
    return Option<Pair<K*, V*>>::new();
  }
}

struct MapIntoIter<K, V>{
  map: Map<K, V>;
  pos: i32;
}
impl<K, V> Iterator<Pair<K, V>> for MapIntoIter<K, V>{
  func next(self): Option<Pair<K, V>>{
    if(self.pos < self.map.len()){
      let idx = self.pos;
      self.pos += 1;
      return Option::new(ptr::deref(self.map.get_pair_idx(idx).unwrap()));
    }
    return Option<Pair<K, V>>::new();
  }
}
impl<K, V> Drop for MapIntoIter<K, V>{
  func drop(*self){
    free(self.map.arr.ptr as i8*);
  }
}

struct ValuesIter<K, V>{
  map: Map<K, V>*;
  pos: i32;
}
impl<K, V> Iterator<V*> for ValuesIter<K, V>{
  func next(self): Option<V*>{
    if(self.pos < self.map.len()){
      let idx = self.pos;
      self.pos += 1;
      return Option::new(self.map.get_idx(idx));
    }
    return Option<V*>::new();
  }
}
