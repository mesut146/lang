// xfail: impl with a foreign module scope spelled inside another module is invisible (only the scope's own module and top level are searched)
mod M{
    struct A{ a: i32; }
    impl A{
        func get(self): i32 { return self.a; }
    }
}
mod N{
    impl M::A{
        func get2(self): i32 { return self.a + 100; }
    }
}
func main(){
    let m = M::A{a: 5};
    assert(m.get() == 5);
    assert(m.get2() == 105);
}
