import std/it

//Macro slice 3: the expansion is hygienic for the names the body *declares*.
//let/for variables, for-each and lambda parameters and match/if-let bindings
//are alpha-renamed per call site, so a macro may use any local name (`t`, `i`,
//`res`, ...) without colliding with the caller's variables -- and a substituted
//argument can no longer be captured by a body local of the same name.
//A name the body does *not* declare still resolves at the call site.
enum E{
    A(val: i32),
    B
}

macro swap_h(a: Expr, b: Expr){
    let t = a;
    a = b;
    b = t;
}

macro add_x(v: Expr){
    let x = 10;
    assert(v == 5);
}

macro twice_i(e: Expr){
    let i = 1;
    let total = 0;
    for (let i = 0;i < e;i = i + 1){
        total = total + 1;
    }
    //a second declaration of the same spelling is its own binding (the first
    //`i` is not reachable after the loop, matching x's no-shadowing rule)
    assert(total == e);
}

macro foreach_sum(a: Expr){
    let total = 0;
    for v in &a{
        total = total + *v;
    }
    assert(total == 6);
}

macro with_lambda(e: Expr){
    let f = |i: i32|: i32{
        return i + 1;
    };
    assert(f(e) == 4);
}

macro param_local(v: i32){
    //a body local may even reuse a parameter's name: from its declaration on,
    //`v` is the body's own binding (renamed), before it the parameter
    assert(v == 7);
    let v = 1;
    assert(v == 1);
}

//the other direction is *not* hygienic: a name the body never declares still
//resolves at the call site (that is how doc/todo's macro-level capture works)
macro use_outer(){
    assert(outer == 5);
}

macro with_match(e: E){
    match &e{
        E::A(n) => {
            //matching a reference binds a pointer (`match &e`)
            assert(*n == 1);
        },
        E::B => {
            assert(false);
        }
    }
}

func main(){
    //body local `t` vs the caller's `t`
    let t = 100;
    let a = 1;
    let b = 2;
    swap_h!(a, b);
    assert(a == 2);
    assert(b == 1);
    assert(t == 100);

    //the argument is itself called `x`: the copy must keep meaning the
    //caller's x, not the body's
    let x = 5;
    add_x!(x);

    //`i` declared twice in one body: the `let i` and the for's `let i`
    let i = 3;
    twice_i!(5);
    assert(i == 3);

    //the for-each variable and the body's `total` are both caller names
    let total = 1;
    let v = 2;
    let arr = [1, 2, 3];
    foreach_sum!(arr);
    assert(total == 1);
    assert(v == 2);

    //a lambda parameter named like the caller's variable
    with_lambda!(i);

    //a body local reusing a parameter's name
    let v2 = 7;
    param_local!(v2);

    //a match binding named like the caller's variable
    let n = 100;
    with_match!(E::A{1});
    assert(n == 100);

    //a body name that is not declared catches the call site's variable
    let outer = 5;
    use_outer!();
}
