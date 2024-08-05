struct Stack<T>{
    list: List<T>;
}

impl<T> Stack<T>{
    func new(): Stack<T>{
        return Stack<T>{
            list: List<T>::new()
        };
    }

    func len(self): i64{
        return self.list.len() as i64;
    }

    func push(self, val: T){
        self.list.add(val);
    }

    func pop(self): T{
        return self.list.remove(self.list.len() - 1);
    }

    func top(self): T*{
        return self.list.get_ptr(self.list.len() - 1);
    }

    func peek(self): T*{
        return self.top();
    }
} 