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

func main(){
    let a = A{a: 1, b: 2};
    print("%s\n", Fmt::str(&a).cstr().ptr());
    assert Fmt::str(&a).eq("A{a: 1, b: 2}");

    let b = B{a: a, b: 3};
    print("%s\n", Fmt::str(&b).cstr().ptr());
    assert Fmt::str(&b).eq("B{a: A{a: 1, b: 2}, b: 3}");

    let e = E::B{b};
    print("%s\n", Fmt::str(&e).cstr().ptr());
    assert Fmt::str(&e).eq("E::B{val: B{a: A{a: 1, b: 2}, b: 3}}");
}