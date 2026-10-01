mod M{
    struct A{ a: i32; }
    impl A{
        func get(self): i32 { return self.a; }
    }
}
mod N{
    struct A{ a: i32; }
    impl A{
        func get(self): i32 { return self.a * 2; }
    }
}
func main(){
    //same type name in two modules must not alias (regression: nested
    //impl methods mangled identically, so N::A::get ran M's body)
    let m = M::A{a: 5};
    let n = N::A{a: 5};
    assert(m.get() == 5);
    assert(n.get() == 10);
    print("dup done\n");
}
