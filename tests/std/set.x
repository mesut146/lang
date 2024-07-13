//sorted set
struct Set<T>{
    head: Option<Node<T>>;
    count: i32;
}
struct Node<T>{
    val: T;
    next: Ptr<Node<T>>;
}
impl<T> Node<T>{
    func new(val: T): Node<T>{
        return Node<T>{val: val, next: Ptr<Node<T>>::new()};
    }
    func new(val: T, next: Ptr<Node<T>>): Node<T>{
        return Node<T>{val: val, next: next};
    }  
    func new(val: T, next: Node<T>): Node<T>{
        return Node<T>{val: val, next: Ptr::new(next)};
    }
}

impl<T> Set<T>{
    func new(): Set<T>{
        return Set{head: Option<Node<T>>::new(), count: 0};
    }
    func len(self): i64{
        return self.count;
    }
    func add(self, e: T){
        if(self.len() == 0){
            ++self.count;
            self.head = Option::new(Node<T>::new(e));
            return;
        }
        let cur: Node<T>* = self.head.get();
        let prev = self.head.get();
        for(let i = 0;i < self.len();++i){
            let cmp = Compare::compare(&e, &cur.val);
            if(cmp == 0){
                //already added
                return;
            }
            if(cmp == -1){
                if(i == 0){
                    let old = self.head.unwrap();
                    self.head = Option::new(Node<T>::new(e));
                    let ptr = self.head.get();
                    ptr.next = Ptr::new(old);
                }else{
                    let cur_tmp = prev.next.unwrap();
                    let new_node = Node<T>::new(e, cur_tmp);
                    prev.next = Ptr::new(new_node);
                }
            }else{
                panic("");
            }
            if(cur.next.is_some()){
                prev = prev.next.get();
                cur = cur.next.get();
            }
        }
        ++self.count;
    }
}

impl<T> Debug for Set<T>{
    func debug(self, f: Fmt*){
        f.print("Set{len: ");
        f.print(&self.count);
        f.print(", elems: ");
        let cur: Node<T>* = self.head.get();
        for(let i = 0;i < self.len();++i){
            if(i > 0){
                f.print(", ");
            }
            f.print(&cur.val);
            if(!cur.next.is_some()){
                break;
            }
            cur = cur.next.get();
        }
        f.print("}");
    }
}