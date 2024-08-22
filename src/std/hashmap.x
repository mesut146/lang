struct HashMap<K, V>{
  buckets: List<Option<Node<K, V>>>;
  count: i64;
}
struct Node<K, V>{
    key: K;
    value: V;
    next: Ptr<Node<K,V>>;
}

impl<K, V> HashMap<K, V>{
    func new(): HashMap<K, V> {
        let capacity = 16;
        let res = HashMap<K, V> {
            buckets: List<Option<Node<K, V>>>::new(capacity),
            count: 0
        };
        for(let i = 0;i < capacity;++i){
            res.buckets.add(Option<Node<K, V>>::new());
        }
        return res;
    }

    func len(self): i64{
        return self.count;
    }

    func get_index(self, key: K*): i64{
        let hash = key.hash();
        let idx = hash % self.buckets.capacity();
        return idx;
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
        }else{
            //collision, goto end of linkedlist
            let node: Node<K,V>* = opt.get();
            if(key.eq(&node.key)){
                node.value = value;
                Drop::drop(key);
                return;
            }
            while(node.next.is_some()){
                node = node.next.get();
                if(key.eq(&node.key)){
                    //already exist, update value
                    node.value = value;
                    Drop::drop(key);
                    return;
                }
            }
            node.next.set(Node{
                key: key,
                value: value,
                next: Ptr<Node<K,V>>::new()
            });
        }
        self.count += 1;
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
            node = node.next.get();
            /*if(node.key == *key){
                return Option::new(&node.value);
            }*/
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