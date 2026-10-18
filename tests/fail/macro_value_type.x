// should-fail: type mismatch i32 vs str
//a value parameter is type-checked when the argument is bound
macro take(a: i32){
    assert(a == 3);
}
func main(){
    take!("s");
}
