struct HashMap<K, V>{
  buckets: List<Option<HashNode<K, V>>>;
  count: i64;//node count
}
struct HashNode<K, V>{
    key: K;
    value: V;
    hash: i64;
    next: Ptr<HashNode<K, V>>;
}

impl<K, V> HashNode<K, V>{
    func unwrap_pair(*self): Pair<K, V>{
        if(self.next.is_some()){
            panic("next must be empty");
        }
        std::no_drop(self.next);
        return Pair::new(self.key, self.value);
    }
}

func default_cap(): i64{
    return 16;
}

impl<K, V> HashMap<K, V>{
    func new(): HashMap<K, V> {
        return HashMap<K, V>::new(default_cap());
    }

    func new(cap: i64): HashMap<K, V> {
        let res = HashMap<K, V> {
            buckets: List<Option<HashNode<K, V>>>::new(cap),
            count: 0,
        };
        res.init(cap);
        return res;
    }

    func init(self, len: i64){
        for(let i = 0;i < len;++i){
            self.buckets.add(Option<HashNode<K, V>>::new());
        }
    }

    func len(self): i64{
        return self.count;
    }

    func empty(self): bool{
        return self.count == 0;
    }
    
    func cap(self): i64{
        return self.buckets.len();
    }

    func get_index(self, key: K*): i64{
        let hash = key.hash();
        return get_index(hash);
    }
    
    func get_index(self, hash: i64): i64{
        if(self.buckets.len() == 0){
            panic("buckets len=0");
        }
        let idx = hash % self.buckets.len();
        return idx;
    }
    
    func get_node(self, key: K*): Option<HashNode<K, V>>*{
        let idx = self.get_index(key);
        return self.buckets.get(idx);
    }

    func rehash(self){
        if(self.len() * 4 < self.buckets.len() * 3){
            return;
        }
        //print("rehash {:?} {},{}\n", std::print_type<HashMap<K, V>>(), self.len(), self.buckets.len());
        let new_cap = self.buckets.len() * 2;
        let new_buckets = List<Option<HashNode<K, V>>>::new(new_cap);
        let old = self.buckets;
        self.buckets = new_buckets;
        self.count = 0;
        self.init(new_cap);

        for bucket_op in old{
            if(bucket_op.is_some()){
                let node = bucket_op.unwrap();
                self.rehash(node);
            }
        }
    }
    
    func rehash(self, node: HashNode<K, V>){
        self.insert(node.key, node.value);
        while(node.next.is_some()){
            let nx = node.next.unwrap();
            node = nx;
            self.insert(node.key, node.value);
        }
        std::no_drop(node.next);
    }

    func insert(self, key: K, value: V): Option<V>{
        let hash = key.hash();
        let idx = self.get_index(hash);
        let opt: Option<HashNode<K, V>>* = self.buckets.get(idx);
        if(opt.is_none()){
            opt.set(HashNode{
                key: key,
                value: value,
                hash: hash,
                next: Ptr<HashNode<K, V>>::new(),
            });
            self.count += 1;
            self.rehash();
            return Option<V>::none();
        }
        //update or collision
        let node: HashNode<K, V>* = opt.get();
        if(key.eq(&node.key)){
            //update
            let res = Option<V>::new(node.value);
            node.value = value;
            node.hash = hash;
            Drop::drop(key);
            return res;
        }
        while(node.next.is_some()){
            node = node.next.get();
            if(key.eq(&node.key)){
                //update
                let res = Option<V>::new(node.value);
                node.value = value;
                node.hash = hash;
                Drop::drop(key);
                return res;
            }
        }
        //collision, insert at end
        let old = node.next.set(HashNode{
            key: key,
            value: value,
            hash: hash,
            next: Ptr<HashNode<K,V>>::new()
        });
        old.drop();
        self.count += 1;
        self.rehash();
        return Option<V>::none();
    }
    
    func add(self, key: K, value: V): Option<V>{
        return self.insert(key, value);
    }

    func get_str(self, s: str): Option<V*>{
        assert(std::print_type<K>().eq("String"));
        let key_str = s.owned();
        let res = self.get(&key_str);
        key_str.drop();
        return res;
    }

    func get(self, key: K*): Option<V*> {
        let hash = key.hash();
        let idx = self.get_index(hash);
        let opt: Option<HashNode<K, V>>* = self.buckets.get(idx);
        if(opt.is_none()){
            return Option<V*>::new();
        }
        let node: HashNode<K, V>* = opt.get();
        if(node.key.eq(key)){
            return Option::new(&node.value);
        }
        if(node.next.is_none()){
            return Option<V*>::new();
        }
        while(node.next.is_some()){
            node = node.next.get();
            if(node.key.eq(key)){
                return Option::new(&node.value);
            }
        }
        return Option<V*>::new();
    }

    func get_or_insert(self, k: K*, vf: func() => V): V*{
        let opt = self.get(k);
        if(opt.is_some()) return opt.unwrap();
        let v = vf();
        self.insert(k, v);
        return get.get(k).unwrap();
    }
    
    func contains(self, key: K*): bool{
        return self.get(key).is_some();
    }
    
    func iter(self): HashMapIter<K, V>{
        return HashMapIter<K, V>{self, 0, Option<HashNode<K, V>*>::none()};
    }

    /*func into_iter(self){
        //todo
    }*/
    
    func keys(self): MapKeysIter<K, V>{
        return MapKeysIter{self, 0, Option<HashNode<K, V>*>::none()};
    }
    
    func pairs(self): List<Pair<K*, V*>>{
        let res = List<Pair<K*, V*>>::new();
        for p in self{
            res.add(Pair::new(p.a, p.b));
        }
        return res;
    }
    
    func remove(self, key: K*): Option<Pair<K, V>>{
        let hash = key.hash();
        let idx = self.get_index(hash);
        let opt: Option<HashNode<K, V>>* = self.buckets.get(idx);
        if(opt.is_none()){
            return Option<Pair<K, V>>::none();
        }
        self.count -= 1;
        let node_ptr: HashNode<K, V>* = opt.get();
        if(key.eq(&node_ptr.key)){
            //head of bucket
            //take ownership of node
            let node: HashNode<K, V> = self.buckets.set(idx, Option<HashNode<K, V>>::new()).unwrap();
            if(node.next.is_none()){
                return Option::new(node.unwrap_pair());
            }else{
                //extract elems & shift next to left
                let next: HashNode<K, V> = node.next.unwrap();
                let key0 = node.key;
                let val0 = node.value;
                self.buckets.get(idx).set(next);
                return Option::new(Pair::new(key0, val0));
            }
        }
        let prev: HashNode<K, V>* = node_ptr;
        while(prev.next.is_some()){
            if(key.eq(&prev.next.get().key)){
                //middle of bucket
                let next: HashNode<K, V> = prev.next.unwrap();
                if(next.next.is_some()){
                    let key0 = next.key;
                    let val0 = next.value;
                    prev.next = next.next;
                    return Option::new(Pair::new(key0, val0));
                }else{
                    //next is at end of bucket
                    prev.next = Ptr<HashNode<K, V>>::new();
                    return Option::new(next.unwrap_pair());
                }
            }
            prev = prev.next.get();
        }
        return Option<Pair<K, V>>::none();
    }
    
    func clear(self){
        self.buckets.clear();
        self.count = 0;
        self.init(default_cap());
    }

    func dump(self){
        for(let i = 0;i < self.buckets.len();++i){
            let opt = self.buckets.get(i);
            if(opt.is_none()) continue;
            let node = opt.get();
            print("{:?}={:?} hash={} i={} idx={}\n\n", node.key, node.value, node.hash, i, self.get_index(node.hash));
            while(node.next.is_some()){
                node = node.next.get();
                print("next ");
                print("{:?}={:?} hash={} i={} idx={}\n\n", node.key, node.value, node.hash, i, self.get_index(node.hash));
            }
        }
    }
}

impl<K, V> Debug for HashMap<K, V>{
    func debug(self, f: Fmt*){
        f.print("{");
        let cnt = 0;
        for(let i = 0;i < self.buckets.len();++i){
            let opt = self.buckets.get(i);
            if(opt.is_none()) continue;
            let node = opt.get();
            if(cnt > 0){
                f.print(", ");
            }
            node.debug(f);
            while(node.next.is_some()){
                node = node.next.get();
                f.print(", ");
                node.debug(f);
            }
            ++cnt;
        }
        f.print("}");
    }
}

impl<K, V> Debug for HashNode<K, V>{
    func debug(self, f: Fmt*){
        f.print("{");
        f.print(&self.key);
        f.print(", ");
        f.print(&self.value);
        f.print("}");
    }
}


//iters
struct HashMapIter<K, V>{
  map: HashMap<K, V>*;
  pos: i32;
  node: Option<HashNode<K, V>*>;
}

impl<K, V> Iterator<Pair<K*, V*>> for HashMapIter<K, V>{
  func next(self): Option<Pair<K*, V*>>{
    if(self.pos >= self.map.buckets.len() && self.node.is_none()){
        return Option<Pair<K*, V*>>::none();
    }
    if(self.node.is_some()){
      let n = self.node.unwrap();
      let res = Option::new(Pair::new(&n.key, &n.value));
      if(n.next.is_some()){
          self.node.set(n.next.get());
      }else{
          self.node.reset();
          self.pos += 1;
      }
      return res;
    }
    let node_opt: Option<HashNode<K, V>>* = self.map.buckets.get(self.pos);
    while(node_opt.is_none() && self.pos < self.map.buckets.len() - 1){
        self.pos += 1;
        node_opt = self.map.buckets.get(self.pos);
    }
    if(node_opt.is_none()) return Option<Pair<K*, V*>>::none();
    
    let node: HashNode<K, V>* = node_opt.get();
    if(node.next.is_some()){
        self.node = Option::new(node.next.get());
    }else{
        self.pos += 1;
    }
    return Option::new(Pair::new(&node.key, &node.value));
  }
}

struct MapNodeIter<K, V>{
  node: Option<HashNode<K, V>*>;
}
impl<K, V> Iterator<Pair<K, V>*> for MapNodeIter<K, V>{
  func next(self): Option<Pair<K, V>>{
      if(self.node.is_none()) return Option<Pair<K, V>>::none();
      let n = self.node.unwrap();
      let res = Option::new(Pair::new(&n.key, &n.value));
      if(self.node.next.is_some()){
          self.node.set(Option::new(self.node.next.get()));
      }else{
          self.node = Option<HashNode<K, V>*>::none();
      }
      return res;
  }
}

struct MapKeysIter<K, V>{
  map: HashMap<K, V>*;
  pos: i32;
  node: Option<HashNode<K, V>*>;
}
impl<K, V> Iterator<K*> for MapKeysIter<K, V>{
  func next(self): Option<K*>{
      if(self.pos >= self.map.buckets.len() && self.node.is_none()){
        return Option<K*>::none();
    }
    if(self.node.is_some()){
      let n = self.node.unwrap();
      let res = Option::new(&n.key);
      if(n.next.is_some()){
          self.node.set(n.next.get());
      }else{
          self.node.reset();
      }
      return res;
    }
    let node_opt: Option<HashNode<K, V>>* = self.map.buckets.get(self.pos);
    while(node_opt.is_none() && self.pos < self.map.buckets.len() - 1){
        self.pos += 1;
        node_opt = self.map.buckets.get(self.pos);
    }
    if(node_opt.is_none()) return Option<K*>::none();
    
    let node: HashNode<K, V>* = node_opt.get();
    if(node.next.is_some()){
        self.node = Option::new(node.next.get());
        self.pos += 1;
    }else{
        self.pos += 1;
    }
    return Option::new(&node.key);
  }
}

func print_iter<T>(it: T){
    while(true){
        let op = it.next();
        if(op.is_none()) break;
        print("{:?} ", op.unwrap());
    }
    print("\n");
}
func to_list<E, IT>(it: IT): List<E>{
    let res = List<E>::new();
    while(true){
        let op = it.next();
        if(op.is_none()) break;
        res.add(op.unwrap());
    }
    return res;
}

func to_list2<IT>(it: IT): List<i32>{
    let res = List<i32>::new();
    while(true){
        let op = it.next();
        if(op.is_none()) break;
        res.add(*op.unwrap());
    }
    return res;
}