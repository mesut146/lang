// should-fail: nested $( ... )* is not supported
//One repetition level in phase A: a repetition inside a repetition would need
//a second list (and the argument pairing rules that come with it).
macro bad(xs: Expr...) {
    $( $( print("{}\n", $xs); )* )*
}

func main(){
    bad!(1, 2);
}
