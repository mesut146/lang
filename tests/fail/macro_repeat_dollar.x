// should-fail: is only valid inside
//`$name` only means something inside `$( ... )*` (there it is the current list
//element); outside a repetition there is no element to substitute.
macro bad(x: Expr) {
    print("{}\n", $x);
}

func main(){
    bad!(1);
}
