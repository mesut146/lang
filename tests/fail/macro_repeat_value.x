// should-fail: is only valid as an element of a list
//`$( ... )*` repeats a *list*: in a single-value position there is nothing to
//expand into. (Statement repetition is a different form: `$( stmts )*`.)
macro bad(xs: Expr...) {
    let y = $( $xs ),*;
    assert(y == 1);
}

func main(){
    bad!(1, 2);
}
