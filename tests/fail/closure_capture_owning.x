//A capturing lambda copies its captured values into the closure object. An
//owning value (String, List<T>, a user Drop type) cannot be captured yet:
//phase B of doc/closures.txt moves it into the closure (the creation site is a
//move) and drops it with the object.
// should-fail: capturing an owning value is not supported yet
import std/string

func main(){
    let s = String::new("hi");
    let lm = ||: i32{ return s.len() as i32; };
    assert(lm() == 2);
}
