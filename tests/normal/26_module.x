mod M{
    //use M;
    
    //#derive(Debug)
    struct A{
        a: i32;
    }
    func useA(): A{
      return A{10};
    }
    impl M::A{
        func get(self): i32 {
            return self.a;
        }
    }
    impl A{//M::A

    }
    mod N{
        struct B{
            b: i32;
        }
        impl A{//M::A

        }
    }
}

impl M::A{
    func new(a: i32): M::A {
        return M::A{a};
    }
}
/*impl M::N::B{
    func new(b: i32): M::N::B {
        return M::N::B{b};
    }
}*/

func main(){
    A{10};
    let a = M::A{a: 5};
    assert(a.a == 5);

    //a = M::A::new(10);
    //assert(a.get() == 10);
}