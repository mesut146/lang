struct Deque<T>{
    arr: [T; 100];
    start_pos: i32;
    end_pos: i32;
}

impl<T> Deque<T>{
    func new(): Deque<T>{
        return Deque<T>{
            arr: [0; 100],
            start_pos: 0,
            end_pos: 0
        };
    }

    func push_back(self, val: T){
        self.arr[self.end_pos] = val;
        self.end_pos += 1;
    }

    func pop_back(self): T{
        --self.end_pos;
        return self.arr[self.end_pos];
    }

    func pop_front(self): T{
        let val = self.arr[self.start_pos];
        ++self.start_pos;
        return val;
    }

    func clear(self){
        self.start_pos = 0;
        self.end_pos = 0;
    }

    func len(self): i32{
        return self.end_pos - self.start_pos;
    }
}