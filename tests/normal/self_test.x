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

    let b = a.get();
    assert b == 100;

    //works bc a is not ptr
    let c = a.unwrap();
    assert c == 100;
}

func ptr_test(){
    let a: A = A{a: 200};
    let ptr: A* = &a;

    let b = ptr.get();
    assert b == 100;

    //cant call unwrap, bc deref from ptr
    let c = ptr.unwrap();
}

func main(){
    normal();
    ptr_test();
}