//#derive(Clone) has to work for the field types people actually use: plain
//values are copied, only owners are cloned (see is_clone_copy in derive.x).
//
//Pre-fix red: every non-pointer field went through `.clone()`, and std has
//Clone impls only for i8..u64 and String (ops.x:50..85, string.x:154), so the
//generated body for `Plain` below failed with "no such method
//bool::clone(bool)" -- and `str`, `f64`, arrays, tuples and plain nested
//structs alike. Owners are unchanged: a drop-typed field still goes through
//clone().
//
//NB: this is a plain -stdpath test (the normal gate does not link the std
//archive, and String + the primitive Clone impls live there), so the owned
//field uses a local #drop type, the generic parameter a local plain type, and
//the assertions only touch fields x can compare: there is no `==` on str
//("string op not supported yet"), so the `str` fields below are covered by the
//fact that the generated body compiles at all.

#derive(Clone)
struct Plain{
    b: bool;
    s: str;
    n: i32;
    f: f64;
    arr: [i32; 2];
    tup: (i32, str);
}

//an owned (drop-typed) field: still cloned
#drop
#derive(Clone)
struct Owner{
    name: str;
    n: i32;
}

//a nested plain struct is itself a value (no drop glue), so it is copied too
#derive(Clone)
struct Nested{
    p: Plain;
    o: Owner;
}

#derive(Clone)
enum Kind{
    Empty,
    Data{v: i32, s: str},
    Owned{o: Owner}
}

//a plain local type: the generic parameter below stays on clone() (the
//instantiation decides) while the concrete plain-value fields are copied
#derive(Clone)
struct P2{
    n: i32;
}

#derive(Clone)
struct Wrapper<T>{
    v: T;
    n: i32;
    b: bool;
}

//Wrapper<P2> has no drop glue, so this field is copied as a value
#derive(Clone)
struct Deep{
    w: Wrapper<P2>;
}

func main(){
    let p = Plain{b: true, s: "abc", n: 1, f: 1.5, arr: [1, 2], tup: (3, "t")};
    let p2 = p.clone();
    assert(p2.b);
    assert(p2.n == 1);
    assert(p2.f == 1.5);
    assert(p2.arr[0] == 1 && p2.arr[1] == 2);
    assert(p2.tup.0 == 3);

    let o = Owner{name: "kim", n: 5};
    let o2 = o.clone();
    assert(o2.n == 5);

    let nested = Nested{p: p.clone(), o: o.clone()};
    let nested2 = nested.clone();
    assert(nested2.p.n == 1);
    assert(nested2.p.arr[1] == 2);
    assert(nested2.o.n == 5);

    let e = Kind::Data{v: 7, s: "d"};
    let e2 = e.clone();
    match e2{
        Kind::Data(v, s) => {
            assert(v == 7);
        },
        _ => {
            assert(false);
        }
    }
    let e3 = Kind::Empty;
    let e4 = e3.clone();
    match e4{
        Kind::Empty => {},
        _ => {
            assert(false);
        }
    }
    let k = Kind::Owned{o: Owner{name: "z", n: 6}};
    let k2 = k.clone();
    match k2{
        Kind::Owned(ko) => {
            assert(ko.n == 6);
        },
        _ => {
            assert(false);
        }
    }

    let w = Wrapper<P2>{v: P2{n: 7}, n: 2, b: true};
    let w2 = w.clone();
    assert(w2.v.n == 7 && w2.n == 2 && w2.b);

    let d = Deep{w: Wrapper<P2>{v: P2{n: 1}, n: 4, b: false}};
    let d2 = d.clone();
    assert(d2.w.v.n == 1 && d2.w.n == 4 && !d2.w.b);

    print("derive clone done\n");
}
