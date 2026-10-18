// should-fail: must be called unqualified
//macros are looked up by bare name (own unit, then imports); a scoped call
//still has no meaning
mod t{
    macro m(x: Expr){
        x;
    }
}
func main(){
    let v = 1;
    t::m!(v);
}
