// should-fail: duplicate parameter x
macro m(x: Expr, x: i32){
    x;
}
func main(){
    let v = 1;
    m!(v, 2);
}
