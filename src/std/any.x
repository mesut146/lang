struct Any{
    box: Box<i8>;
    type: String;
    //drop_f: func(i8*): void;
}
   
impl Any{
    func new(): Any{
        return Any{box: Box::new(0i8), type: "".owned()};
    }
    func new<T>(val: T): Any{
        let b = Box<T>::new(val);
        let b2 = ptr::deref!(&b as Box<i8>*);
        std::no_drop(b);
        //Drop::drop as func(T): void
        //let drop_f = T::drop;
        return Any{box: b2, type: std::print_type<T>().owned()};
    }

    func get<T>(self): T*{
        return self.box.get() as T*;
    }

    func drop2<T>(*self){
        let val: T = ptr::deref!(self.box.get() as T*);
        Drop::drop(val);
        std::no_drop(self);
    }
}

impl Drop for Any{
    func drop(*self){
        panic("any must be drop manually");
    }
}

impl Debug for Any{
    func debug(self, f: Fmt*){
        f.print("Any<");
        f.print(&self.type);
        f.print(">(");
        f.print(">)");
    }
}