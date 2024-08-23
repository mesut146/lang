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
    ptr: T*;
}

#derive(Debug)
enum GenEnum<T>{
    A,
    B(val: T, ptr: T*)
}


func main(){
    let a = A{a: 1, b: 2};
    let s1 = Fmt::str(&a);
    assert_eq(s1, "A{a: 1, b: 2}");

    let b = B{a: a, b: 3};
    let s2 = Fmt::str(&b);
    assert(s2.eq("B{a: A{a: 1, b: 2}, b: 3}"));
    s2.drop();

    let e = E::B{b};
    let s3 = Fmt::str(&e);
    assert_eq(s3, "E::B{val: B{a: A{a: 1, b: 2}, b: 3}}");

    let x = 123;
    let x_str = i64::print_hex(&x as u64);
    let p = Ptr{a: 10, b: &x};
    assert_eq(Fmt::str(&p), format("Ptr{a: 10, b: {}}", &x_str));

    let g = Gen{val: 456, ptr: &x};
    let s4 = Fmt::str(&g);
    assert_eq(s4, format("Gen<i32>{val: 456, ptr: {}}", &x_str));

    let xptr = &x;
    let x2_str = i64::print_hex(&xptr as u64);
    let g2 = Gen{val: &x, ptr: &xptr};
    assert_eq(Fmt::str(&g2), format("Gen<i32*>{val: {}, ptr: {}}", x_str, x2_str));

    let ge = GenEnum<i32>::A;
    assert_eq(Fmt::str(&ge), "GenEnum<i32>::A");

    //let ge2 = GenEnum::B{456, &x};//err not cached
    let ge2 = GenEnum<i32>::B{456, &x};
    assert_eq(Fmt::str(&ge2), format("GenEnum<i32>::B{val: 456, ptr: {}}", x_str));

    x_str.drop();
    x2_str.drop();
}