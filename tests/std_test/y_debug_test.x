#derive(Debug)
struct A{
    a: i32;
    b: i32;
}

#derive(Debug)
struct B{
    a: A;
    b: i32;
}

#derive(Debug)
enum E{
    A,
    B(val: B)
}

#derive(Debug)
struct Ptr{
    a: i32;
    b: i32*;
}

func main(){
    let a = A{a: 1, b: 2};
    print("{}\n", &a);
    assert(Fmt::str(&a).eq("A{a: 1, b: 2}"));

    let b = B{a: a, b: 3};
    assert(Fmt::str(&b).eq("B{a: A{a: 1, b: 2}, b: 3}"));

    let e = E::B{b};
    assert(Fmt::str(&e).eq("E::B{val: B{a: A{a: 1, b: 2}, b: 3}}"));

    let x = 123;
    let p = Ptr{a: 10, b: &x};
    print("x={}\n", &p);
    //assert(Fmt::str(&p).str().starts_with("Ptr{a: 10, b: 0x"));
}