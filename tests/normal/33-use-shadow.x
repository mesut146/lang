mod M{
    struct A{ a: i32; }
}
struct A{
    b: i32;
}
use M::A;
func main(){
    //a local definition always wins over a use alias
    let a = A{b: 1};
    assert(a.b == 1);
    //the alias target is still reachable spelled out
    let m = M::A{a: 2};
    assert(m.a == 2);
    print("shadow done\n");
}
