import own/common

struct Holder{
    a: A;
}
enum E{
    V(val: Holder),
    W
}
//read-only use of a pointer-match binding.
func show(e: E*, id: i32){
    match e{
        E::V(h) => {
            h.a.check(id);
        },
        _ => {}
    }
}
func main(){
    let h = Holder{a: A::new(30)};
    let e = E::V{val: h};
    show(&e, 30);
    print("show done\n");
}
