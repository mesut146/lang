mod M{
    struct A{
        a: i32;
    }
    impl A{
        func get(self): i32 {
            return self.a;
        }
        func incr_scoped(self): M::A {
            return M::A{a: self.a + 1};
        }
        func incr(self): A {
            return M::A{a: self.a + 1};
        }
    }
}
func main(){
    let a = M::A{a: 5};
    assert(a.get() == 5);
    //chained calls through scoped and unscoped returns
    assert(a.incr_scoped().get() == 6);
    assert(a.incr().get() == 6);
    assert(a.incr().incr().get() == 7);
    print("nested impl done\n");
}
