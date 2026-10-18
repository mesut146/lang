// should-fail: is reserved (builtin macro)
macro print(a: Expr){
    a;
}
func main(){
    let v = 1;
    print!(v);
}
