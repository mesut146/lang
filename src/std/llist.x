//#derive(Debug)
struct LinkedList<T>{
    head: Option<Node<T>>;
}

//#derive(Debug)
struct Node<T>{
    val: T;
    next: Option<Box<Node<T>>>;
}

impl<T> Node<T>{
    func new(val: T): Node<T>{
        return Node<T>{val, Option<Box<Node<T>>>::new()};
    }
    func new(val: T, next: Node<T>): Node<T>{
        return Node<T>{val, Option::new(Box::new(next))};
    }
}

impl<T> LinkedList<T>{
    func new(): LinkedList<T>{
        return LinkedList<T>{head: Option<Node<T>>::new()};
    }
    func add(self, val: T): T*{
        if(self.head.is_none()){
            self.head.set(Node::new(val));
            return &self.head.get().val;
        }
        let last = self.head.get();
        while(last.next.is_some()){
            last = last.next.get().get();
        }
        last.next.set(Box::new(Node::new(val)));
        &last.next.get().get().val
    }
    func clear(self){
        self.head = Option<Node<T>>::new();
    }
}

impl<T> Debug for Node<T>{
    func debug(self, f: Fmt*){
        self.val.debug(f);
        if(self.next.is_some()){
            f.print(", ");
            self.next.get().get().debug(f);
        }
    }
}
impl<T> Debug for LinkedList<T>{
    func debug(self, f: Fmt*){
        f.print("[");
        if(self.head.is_some()){
            self.head.get().debug(f);
        }
        f.print("]");
    }
}