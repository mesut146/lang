//user-defined macros: `macro name(p: Expr){ ... }` + `name!(...)` expands by
//copying the body per call site, with every reference to a parameter replaced
//by a copy of the argument expression (`Expr` is a syntax slot, not a value).
//Statement and expression position, macros calling macros, and the expansion
//being a scope of its own are all exercised here.
macro swap(a: Expr, b: Expr){
    let t = a;
    a = b;
    b = t;
}

macro incr(x: Expr){
    x = x + 1;
    x = x + 1;
}

macro add_two(x: Expr){
    incr!(x);
    incr!(x);
}

macro square(x: Expr){
    x * x
}

func main(){
    let a = 1;
    let b = 2;
    swap!(a, b);
    assert(a == 2);
    assert(b == 1);
    incr!(a);
    assert(a == 4);
    //a macro body may call another macro; each expansion re-copies the body
    add_two!(b);
    assert(b == 5);
    //the expansion is a scope: swap!'s `t` is not visible here
    let t = 7;
    assert(t == 7);
    //expression position: the body's trailing expression is the value
    assert(square!(3) == 9);
    let v = square!(a);
    assert(v == 16);
}
