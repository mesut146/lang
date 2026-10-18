// should-fail: macro swap expects 2 args, got 1
macro swap(a: Expr, b: Expr){
    let t = a;
    a = b;
    b = t;
}
func main(){
    let x = 1;
    let y = 2;
    swap!(x);
}
