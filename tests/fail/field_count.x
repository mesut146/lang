// should-fail: field count mismatch
struct B{ b: i32; c: i32; }
func main(){
    let x = B{b: 1};
}
