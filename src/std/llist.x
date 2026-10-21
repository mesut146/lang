//#derive(Debug)
struct LinkedList<T>{
    head: Option<LNode<T>>;
}

//#derive(Debug)
struct LNode<T>{
    val: T;
    next: Option<Box<LNode<T>>>;
}

impl<T> LNode<T>{
    func new(val: T): LNode<T>{
        return LNode<T>{val, Option<Box<LNode<T>>>::new()};
    }
    
    func new(val: T, next: LNode<T>): LNode<T>{
        return LNode<T>{val, Option::new(Box::new(next))};
    }
}

impl<T> LinkedList<T>{
    func new(): LinkedList<T>{
        return LinkedList<T>{head: Option<LNode<T>>::new()};
    }
    
    func len(self): i32{
        if(self.head.is_none()) return 0;
        let c = 1;
        let cur = self.head.get();
        while(cur.next.is_some()){
            cur = cur.next.get().get();
            c+=1;
        }
        return c;
    }
    
    func empty(self): bool{
        return self.head.is_none();
    }
    
    func last(self): T*{
        return self.get(self.len() - 1);
    }
    
    func get(self, pos: i32): T*{
        let cur = self.head.get();
        let i = 0;
        while(i < pos){
            if(cur.next.is_some()){
                cur = cur.next.get().get();
                i += 1;
            }else{
                break;
            }
        }
        if(i == pos){
            return &cur.val;
        }
        panic("index out of pos {} len: {}", pos, self.len());
    }
    
    func remove(self, pos: i32){
        if(pos == 0){
            if(self.head.get().next.is_some()){
                //take (not unwrap().next...): moving a field out of the
                //temporary would double-drop it. Whole-temp takes leave
                //None behind, so every temp drops only what remains; the
                //old head's val still drops exactly once via its temp.
                let nx = self.head.take().unwrap().next.take().unwrap().unwrap();
                self.head = Option<LNode<T>>::new(nx);
            }else{
                self.head = Option<LNode<T>>::new();
            }
            return;
        }
        let cur = self.head.get();
        let i = 1;
        while(i < pos){
            if(cur.next.is_some()){
                cur = cur.next.get().get();
                i += 1;
            }else{
                break;
            }
        }
        if(i == pos){
            //take-chain (not unwrap().unwrap().next): field moves out of
            //temps double-drop. Each take()/unwrap() consumes a whole temp
            //or leaves None behind, so no named partial is ever recorded;
            //every temp drops only what remains, and the bypassed node's
            //val still drops exactly once via its temp. (Box::unwrap leaks
            //the box shell itself, as before.) The final take() is
            //infallible, so removing the last element needs no guard.
            let nx = cur.next.take().unwrap().unwrap().next.take();
            cur.next = nx;
        }
    }
    
    func add(self, val: T): T*{
        if(self.head.is_none()){
            self.head.set(LNode::new(val));
            return &self.head.get().val;
        }
        let last = self.head.get();
        while(last.next.is_some()){
            last = last.next.get().get();
        }
        last.next.set(Box::new(LNode::new(val)));
        //&last.next.get().get().val
        let bx = last.next.get();
        return &bx.get().val;
    }
    
    func clear(self){
        self.head = Option<LNode<T>>::new();
    }
    
    func indexOf(self, val: T*): i32{
        let i = 0;
        if(self.head.is_none()) return -1;
        let cur = self.head.get();
        while(true){
            if(Eq::eq(cur.val, val)) return i;
            if(cur.next.is_some()){
              cur = cur.next.get().get();
            }else{
                break;
            }
            i += 1;
        }
        return -1;
    }
}

impl<T> Debug for LNode<T>{
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

impl<T> Display for LNode<T>{
    func fmt(self, f: Fmt*){
        Debug::debug(self, f);
    }
}
impl<T> Display for LinkedList<T>{
    func fmt(self, f: Fmt*){
        Debug::debug(self, f);
    }
}