// should-fail: use after move
#drop
struct S{
    v: i32;
}
impl Drop for S{
    func drop(*self){
    }
}
macro take2(p: Expr){
    consume(p);
    consume(p);
}
func consume(s: S){
}
func main(){
    let s = S{v: 1};
    take2!(s);
}
