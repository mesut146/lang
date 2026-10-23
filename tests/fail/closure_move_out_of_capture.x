//A captured value is borrowed from the closure object, which owns it: the
//generated method may run many times, so moving the value out would hand the
//same allocation to a callee on the first call and leave a stale field for the
//closure's drop.
// should-fail: cannot move out of a captured value
import std/string

func take(s: String): i32{
    return s.len() as i32;
}

func main(){
    let s = String::new("hi");
    let f = ||: i32{ return take(s); };
    assert(f() == 2);
}
