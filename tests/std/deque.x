struct Deque<T>{
    arr: [T; 100];
    start_pos: i32;
    end_pos: i32;
    size: i32;
}

impl<T> Debug for Deque<T>{
    func debug(self, f: Fmt*){
        f.print("[");
        for(let i = self.start_pos;i <= self.end_pos;++i){
            f.print(&i);
            f.print("=");
            f.print(&self.arr[i]);
            if(i != self.end_pos){
                f.print(",");
            }
        }
        f.print("]");
    }
}

impl<T> Deque<T>{
    func new(): Deque<T>{
        return Deque<T>{
            arr: [0; 100],
            start_pos: 50,
            end_pos: 50,
            size: 0
        };
    }

    func len(self): i32{
        //return self.end_pos - self.start_pos;
        return self.size;
    }

    func empty(self): bool{
        return self.len() == 0;
    }

    func clear(self){
        self.start_pos = 50;
        self.end_pos = 50;
        self.size = 0;
    }

    func push_back(self, val: T){
        if(!self.empty()){
            self.end_pos += 1;
        }
        self.arr[self.end_pos] = val;
        self.size += 1;
    }
    func push_front(self, val: T){
        if(!self.empty()){
            self.start_pos -= 1;
        }
        self.arr[self.start_pos] = val;
        self.size += 1;
    }

    func pop_back(self): T{
        assert(!self.empty());
        let val = self.arr[self.end_pos];
        if(self.len() > 1){
            --self.end_pos;
        }
        self.size -= 1;
        return val;
    }

    func pop_front(self): T{
        assert(!self.empty());
        let val = self.arr[self.start_pos];
        if(self.len() > 1){
            ++self.start_pos;
        }
        self.size -= 1;
        return val;
    }

    func peek_front(self): T*{
        assert(!self.empty());
        return &self.arr[self.start_pos];
    }
    func peek_back(self): T*{
        assert(!self.empty());
        return &self.arr[self.end_pos];
    }

    func dump(self){
        print("size: {} start: {} end: {}\n", self.size, self.start_pos, self.end_pos);
    }
}