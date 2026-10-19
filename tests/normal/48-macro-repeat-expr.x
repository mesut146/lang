//User macros slice 4b (doc/codegen_macros.txt phase A): `$( <exprs> ),*` in an
//expression list -- arguments, array elements, tuple elements. The elements are
//repeated once per list element; the `,` before `*` is spelling only (the
//enclosing list supplies the commas), so the list's own separator follows the
//repetition.
macro arr(xs: Expr...) {
    [$( $xs ),*]
}

macro sum3(a: Expr, b: Expr, c: Expr) {
    a + b + c
}

macro fwd(xs: Expr...) {
    //the repetition becomes another macro's argument list
    sum3!($( $xs ),*)
}

macro with_tail(xs: Expr...) {
    //the tuple's own separator follows the repetition
    ($( $xs ),*, 99)
}

macro twice_each(xs: Expr...) {
    //the body may use the element more than once per iteration
    [$( $xs, $xs ),*]
}

func main(){
    let a = arr!(1, 2, 3);
    assert(a[0] == 1 && a[1] == 2 && a[2] == 3);
    assert(fwd!(1, 2, 3) == 6);
    assert(fwd!(4, 5, 6) == 15);
    let t = with_tail!(7, 8);
    assert(t.0 == 7);
    assert(t.1 == 8);
    assert(t.2 == 99);
    let d = twice_each!(5, 6);
    assert(d[0] == 5 && d[3] == 6);
}
