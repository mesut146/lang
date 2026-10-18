// should-fail: no macro 'm' in 'other'
//a scoped call must match the module the macro was declared in
mod t{
    macro m(x: Expr){
        x;
    }
}
func main(){
    let v = 1;
    other::m!(v);
}
