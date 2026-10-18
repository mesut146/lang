// should-fail: parameter 'x' must be declared as
macro m(x: i32){
    x = x;
}
func main(){
    let v = 1;
    m!(v);
}
