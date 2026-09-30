// should-fail: not found from candidates
func add(a: i32, b: i32): i32{
    return a + b;
}
func main(){
    assert(add(1) == 1);
}
