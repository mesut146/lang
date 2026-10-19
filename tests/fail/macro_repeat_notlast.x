// should-fail: list parameter must be last
//`xs: Expr...` takes every remaining argument, so it cannot be followed by a
//fixed parameter.
macro bad(xs: Expr..., n: i32) {
    print("{}\n", $xs);
}

func main(){
    bad!(1, 2, 3);
}
