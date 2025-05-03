mod M{
    //#derive(Debug)
    struct A{
        a: i32;
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

    a = M::A::new(10);
}