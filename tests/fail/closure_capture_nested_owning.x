//A nested closure captures through the outer one, so an owning value would be
//copied out of the outer closure's field: two owners, no Clone bound to make it
//a real copy. Plain values work (tests/normal/65-closure-owning-capture.x).
// should-fail: capturing an owning value through a lambda is not supported yet
import std/string

func main(){
    let s = String::new("hi");
    let outer = ||: i32{
        let inner = ||: i32{ return s.len() as i32; };
        return inner();
    };
    assert(outer() == 2);
}
