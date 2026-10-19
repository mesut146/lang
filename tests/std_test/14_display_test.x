//#derive(Display) is the opt-in default dump for `{}`: the same shape as
//#derive(Debug) (Type{field: value} / Type::Variant(...)), with fmt instead of
//debug. It is a convenience, not a replacement for a hand-written Display: an
//explicit impl makes the derive step aside (has_trait_impl).
//
//Pre-fix red: `generate_derive decl: A der: 'Display'` -- the name was not
//dispatched at all.

#derive(Display)
struct A{
    a: i32;
    b: i32;
}

#derive(Display)
struct Nested{
    p: A;
    ok: bool;
}

#derive(Display)
enum E{
    Empty,
    B(val: i32),
    C{x: i32, y: str}
}

#derive(Display)
struct Gen<T>{
    val: T;
}

#derive(Display)
struct Ptr{
    a: i32;
    b: i32*;
}

//the hand-written impl wins: the derive is skipped for this type
#derive(Display)
struct Manual{
    a: i32;
}

impl Display for Manual{
    func fmt(self, f: Fmt*){
        f.print("manual");
    }
}

func main(){
    let a = A{a: 1, b: 2};
    assert_eq(to_string(&a), "A{a: 1, b: 2}");

    //a nested Display field goes through Display::fmt
    let n = Nested{p: A{a: 3, b: 4}, ok: true};
    assert_eq(to_string(&n), "Nested{p: A{a: 3, b: 4}, ok: true}");

    let e = E::B{val: 3};
    assert_eq(to_string(&e), "E::B{val: 3}");
    let e2 = E::Empty;
    assert_eq(to_string(&e2), "E::Empty");
    let e3 = E::C{x: 4, y: "s"};
    assert_eq(to_string(&e3), "E::C{x: 4, y: s}");

    //a generic field goes through the std::display helper (the type parameter
    //is not known when the impl is generated)
    let g = Gen<i32>{val: 5};
    assert_eq(to_string(&g), "Gen<i32>{val: 5}");

    //a pointer field prints as hex, exactly like Debug
    let x = 123;
    let x_str = i64::print_hex(&x as u64);
    let p = Ptr{a: 10, b: &x};
    assert_eq(to_string(&p), format("Ptr{{a: 10, b: {}}", &x_str));

    let m = Manual{a: 1};
    assert_eq(to_string(&m), "manual");

    //`{}` itself, without the to_string wrapper
    let f = Fmt::new();
    a.fmt(&f);
    assert_eq(f.unwrap(), "A{a: 1, b: 2}");

    print("display derive done\n");
}
