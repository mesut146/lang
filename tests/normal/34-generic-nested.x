mod M{
    struct Wrapper<T>{
        v: T;
    }
    impl<T> Wrapper<T>{
        func get(self): T{
            return self.v;
        }
        func wrap(x: T): M::Wrapper<T>{
            return M::Wrapper{v: x};
        }
    }
}
func main(){
    //inferred literal + instance method
    let b = M::Wrapper{v: 7};
    assert(b.get() == 7);
    //annotated construction
    let c = M::Wrapper<i32>{v: 8};
    assert(c.get() == 8);
    //static generic call on bare scope
    let d = M::Wrapper::wrap(9);
    assert(d.get() == 9);
    //static generic call on annotated scope
    let e = M::Wrapper<i32>::wrap(10);
    assert(e.get() == 10);
    print("gen nested done\n");
}
