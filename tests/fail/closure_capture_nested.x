//A lambda created inside another lambda cannot capture the outer function's
//locals yet: the inner creation site would have to read the outer capture, and
//only direct captures are threaded through in phase A (doc/closures.txt).
// should-fail: capturing through a lambda is not supported yet
func main(){
    let x = 1;
    let outer = ||: i32{
        let inner = ||: i32{ return x; };
        return inner();
    };
    assert(outer() == 1);
}
