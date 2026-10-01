import own/common

struct Holder{
    a: A;
}
enum E{
    V(val: Holder),
    W
}
//match on a pointer, mutate through the binding: the binding must be
//registered (as a pointer) or drop_lhs panics with "var not found".
func test(e: E*){
    match e{
        E::V(h) => {
            h.a = A::new(20);
        },
        _ => {}
    }
}
func main(){
    let h = Holder{a: A::new(10)};
    let e = E::V{val: h};
    test(&e);
    //old A(10) dropped by the field assign inside test()
    check_ids(10);
    reset();
}
