// should-fail: must be used as '$xs' inside
//A list parameter is not a value: inside the repetition the element is spelled
//`$xs`, and outside it there is no single element to read.
macro bad(xs: Expr...) {
    $( print("{}\n", xs); )*
}

func main(){
    bad!(1, 2);
}
