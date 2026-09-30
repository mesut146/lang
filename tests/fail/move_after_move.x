// should-fail: use after move
#drop
struct A{ a: i32; }
impl Drop for A{
    func drop(*self){
    }
}
func send(a: A){
}
func main(){
    let a = A{a: 1};
    send(a);
    send(a);
}
