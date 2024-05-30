struct A{
    a: i32;
}

impl A{
    func unwrap(*self): i32{
        return self.a;
    }
    func get(self): i32{
        return self.a;
    }
}

func normal(){
    let a: A = A{a: 100};

    let b = a.get();//a coerce to ptr
    assert(b == 100);

    assert(A::get(&a) == 100);

    //works bc a is not ptr
    let c = a.unwrap();
    assert(c == 100);

    let a2 = A{a: 111};
    assert(A::unwrap(a2) == 111);
}

func ptr_test(){
    let a: A = A{a: 200};
    let ptr: A* = &a;

    let b = ptr.get();
    assert(b == 200);

    //cant call unwrap, bc deref from ptr
    //let c = ptr.unwrap();
}

func main(){
    normal();
    ptr_test();
    print("self_test done\n");
}