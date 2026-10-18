// should-fail: body declares `x`, which is a parameter
//x has no shadowing, so a body local named like a parameter would silently
//refer to the parameter instead (the reference is substituted)
macro m(x: Expr){
    let x = 1;
    x;
}
func main(){
    let v = 1;
    m!(v);
}
