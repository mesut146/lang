impl<T> [T]{
    func len(self): i64;
    func ptr(self): T*;
    
    func new(ptr: T*, start: i64, end: i64): [T]{
        assert(start >= 0);
        assert(start <= end);
        return ptr[start..end];
    }

    func validate(self){
        assert(len() >= 0);
    }

    func get(self, i: i64): T*{
        if(i < 0 || i >= len()){
            panic("index out of bounds {} len = {}", index, len());
        }
        return ptr::get(self.ptr(), i);
    }
  }