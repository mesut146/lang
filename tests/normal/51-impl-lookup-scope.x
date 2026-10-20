mod M{
    struct A{ a: i32; }
    impl A{
        func get(self): i32 { return self.a; }
    }
}
struct A{
    a: i32;
}
impl A{
    func get(self): i32 { return self.a * 3; }
}

func main(){
    //impl lookup is memoized per unit and receiver type. A scoped receiver
    //(M::A) and the top-level type of the same name must not share an entry:
    //keying the memo on the bare name aliased them.
    let m = M::A{a: 5};
    let a = A{a: 5};
    assert(m.get() == 5);
    assert(a.get() == 15);
    print("impl scope done\n");
}
