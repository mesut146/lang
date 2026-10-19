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

//a free body name (not declared in the body, not a parameter) is resolved at
//the call site; a top-level function is the ordinary case (a caller *local* of
//that name is a capture and is rejected -- tests/fail/macro_capture_local.x)
func twice(n: i32): i32{
    return n * 2;
}

macro show_double(x: Expr){
    print("double {}\n", twice(x));
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
    //a body name that only exists at module level, with no caller local of
    //that spelling, still resolves (and prints)
    let n = 3;
    show_double!(n);
}
