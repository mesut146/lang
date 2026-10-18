// should-fail: is unit-local, not scoped
mod t{
    macro m(x: Expr){
        x;
    }
}
func main(){
    let v = 1;
    t::m!(v);
}
