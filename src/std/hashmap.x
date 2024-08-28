struct HashMap<K, V>{
  buckets: List<Option<Node<K, V>>>;
  count: i64;//node count
  bucket_len: i64;//filled buckets
}
struct Node<K, V>{
    key: K;
    value: V;
    next: Ptr<Node<K,V>>;
}

func default_cap(): i64{
    return 16;
}

impl<K, V> HashMap<K, V>{
    func new(): HashMap<K, V> {
        let res = HashMap<K, V> {
            buckets: List<Option<Node<K, V>>>::new(default_cap()),
            count: 0,
            bucket_len: 0
        };
        res.init(default_cap());
        return res;
    }
    func init(self, len: i64){
        for(let i = 0;i < len;++i){
            self.buckets.add(Option<Node<K, V>>::new());
        }
    }

    func len(self): i64{
        return self.count;
    }

    func get_index(self, key: K*): i64{
        let hash = key.hash();
        let idx = hash % self.buckets.len();
        return idx;
    }

    func rehash(self){
        let load_factor = 1.0 * self.count / self.buckets.len();
        print("load_factor = ");
        printf("%f\n", load_factor);
        if(true /*load_factor <= 0.7*/){
            return;
        }
        let new_cap = self.buckets.len() * 2;
        let new_buckets = List<Option<Node<K, V>>>::new(new_cap);
        let old = self.buckets;
        self.buckets = new_buckets;
        self.bucket_len = 0;
        self.count = 0;
        self.init(new_cap);

        for bucket_op in old{
            if(bucket_op.is_some()){
                let bucket = bucket_op.unwrap();
                self.insert(bucket.key, bucket.value);
                //next
            }
        }
    }

    func insert(self, key: K, value: V) {
        let idx = self.get_index(&key);
        let opt: Option<Node<K, V>>* = self.buckets.get_ptr(idx);
        if(opt.is_none()){
            opt.set(Node{
                key: key,
                value: value,
                next: Ptr<Node<K,V>>::new()
            });
            self.bucket_len += 1;
            self.count += 1;
            self.rehash();
        }else{
            //update or collision
            let node: Node<K,V>* = opt.get();
            if(key.eq(&node.key)){
                //update
                node.value = value;
                Drop::drop(key);
                return;
            }
            while(node.next.is_some()){
                node = node.next.get();
                if(key.eq(&node.key)){
                    //update
                    node.value = value;
                    Drop::drop(key);
                    return;
                }
            }
            //collision, insert at end
            node.next.set(Node{
                key: key,
                value: value,
                next: Ptr<Node<K,V>>::new()
            });
            self.count += 1;
            self.rehash();
        }
    }

    func get(self, key: K*): Option<V*> {
        let idx = self.get_index(key);
        let opt: Option<Node<K, V>>* = self.buckets.get_ptr(idx);
        if(opt.is_none()){
            return Option<V*>::new();
        }
        let node: Node<K, V>* = opt.get();
        if(node.next.is_none()){
            return Option::new(&node.value);
        }
        while(node.next.is_some()){
            if(node.key.eq(key)){
                return Option::new(&node.value);
            }
            node = node.next.get();
        }
        return Option::new(&node.value);
    }
}

impl<K, V> Debug for HashMap<K, V>{
    func debug(self, f: Fmt*){
        f.print("{");
        let cnt = 0;
        for(let i = 0;i < self.buckets.len();++i){
            let opt = self.buckets.get_ptr(i);
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

impl<K, V> Debug for Node<K, V>{
    func debug(self, f: Fmt*){
        f.print("{");
        f.print(&self.key);
        f.print(", ");
        f.print(&self.value);
        f.print("}");
    }
}