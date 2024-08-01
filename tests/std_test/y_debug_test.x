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

#derive(Debug)
struct Gen<T>{
    val: T;
}

func main(){
    let a = A{a: 1, b: 2};
    let s1 = Fmt::str(&a);
    assert(s1.eq("A{a: 1, b: 2}"));
    s1.drop();

    let b = B{a: a, b: 3};
    let s2 = Fmt::str(&b);
    assert(s2.eq("B{a: A{a: 1, b: 2}, b: 3}"));
    s2.drop();

    let e = E::B{b};
    let s3 = Fmt::str(&e);
    assert_eq(s3.str(), "E::B{val: B{a: A{a: 1, b: 2}, b: 3}}");
    s3.drop();

    let x = 123;
    let p = Ptr{a: 10, b: &x};
    print("x={}\n", &p);
    //assert(Fmt::str(&p).str().starts_with("Ptr{a: 10, b: 0x"));

    let g = Gen{val: 456};
    let s4 = Fmt::str(&g);
    print("s4={}\n", &s4);
    assert_eq(s4.str(), "Gen<i32>{val: 456}");
    s4.drop();
}