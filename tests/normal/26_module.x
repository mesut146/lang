mod M{
    //use M;
    
    //#derive(Debug)
    struct A{
        a: i32;
    }
    impl M::A{
        func get(self): i32 {
            return self.a;
        }
    }
    impl A{

    }
}

impl M::A{
    func new(a: i32): M::A {
        return M::A{a};
    }
}

func main(){
    let a = M::A{a: 5};
    assert(a.a == 5);

    /*a = M::A::new(10);
    assert(a.get() == 10);*/
}