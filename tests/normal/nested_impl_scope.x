// xfail: unscoped nested impl headers don't inherit module scope
mod M{
    struct A{
        a: i32;
    }
    impl A{
        func get(self): i32 {
            return self.a;
        }
    }
}
func main(){
    let a = M::A{a: 5};
    assert(a.get() == 5);
}
