import std/hashmap


struct HashSet<T>{
    map: HashMap<T, bool>;
}

impl<T> HashSet<T>{
    func new(): HashSet<T>{
        return HashSet<T>{HashMap<T, bool>::new()};
    }
    func len(self): i64{
        return self.map.len();
    }
    func add(self, e: T): bool{
        return self.map.add(e, true).is_none();
    }
    func insert(self, e: T): bool{
        return self.map.insert(e, true).is_none();
    }
    func contains(self, k: T*): bool{
        return self.map.get(k).is_some();
    }
    func remove(self, k: T*): Option<T>{
        let opt = self.map.remove(k);
        if(opt.is_some()){
            return Option::new(opt.unwrap().a);
        }
        return Option<T>::none();
    }
    func iter(self): HashSetIter<T>{
        return HashSetIter<T>{self.map.iter()};
    }
}

struct HashSetIter<T>{
    it: HashMapIter<T, bool>;
}
impl<T> Iterator<T*> for HashSetIter<T>{
  func next(self): Option<T*>{
      let op = self.it.next();
      if(op.is_some()){
          return Option::new(op.unwrap().a);
      }
      return Option<T*>::none();
  }
}

impl<T> Debug for HashSet<T>{
    func debug(self, f: Fmt*){
        f.print("[");
        let first = true;
        for e in self{
            if(!first) f.print(", ");
            Debug::debug(e, f);
            first = false;
        }
        f.print("]");
    }
    
}