// should-fail: macro m already defined
macro m(x: Expr){
    x;
}
macro m(x: Expr){
    x;
}
func main(){
    let v = 1;
    m!(v);
}
