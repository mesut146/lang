//User macros slice 4 (doc/codegen_macros.txt phase A): a `T...` rest parameter
//plus `$( ... )*` repetition. The list parameter takes every remaining argument
//and is usable only as `$name` inside a repetition; the body is copied once per
//element, so the declarations inside it are alpha-renamed again per iteration
//(each copy's `t` is its own binding).
macro check_all(xs: Expr...) {
    $( assert($xs > 0); )*
}

macro print_all(xs: Expr...) {
    $( print("v={}\n", $xs); )*
}

macro each_local(xs: Expr...) {
    $( let t = $xs; assert(t > 0); let u = t + 1; assert(u == t + 1); )*
}

macro nested(xs: Expr...) {
    //a macro call per element (the element becomes its argument)
    $( print_all!($xs); )*
}

macro guarded(xs: Expr...) {
    //a repetition is spliced wherever it appears, including a nested block
    if(true){
        $( print("g={}\n", $xs); )*
    }
}

macro paired(xs: Expr...) {
    //a fixed parameter before the list
    $( print("{}:{}\n", $xs, true); )*
}

macro count_all(x: Expr...) {
    let n = 0;
    $( n = n + 1; )*
    n
}

func main(){
    check_all!(1, 2, 3);
    check_all!(7);
    //zero elements: the repetition emits nothing
    check_all!();
    print_all!(4, 5);
    each_local!(1, 2);
    nested!(8, 9);
    guarded!(10);
    paired!(11, 12);
    //expression macro: the repetition is a statement list, the result follows
    assert(count_all!(1, 2, 3) == 3);
    assert(count_all!() == 0);
}
