//Capturing an owning value moves it into the closure object (doc/closures.txt
//section 9): the caller keeps no handle, so reading it afterwards is a use
//after move, exactly like passing it by value to a call.
// should-fail: use after move
import std/string

func main(){
    let s = String::new("hi");
    let f = ||: i32{ return s.len() as i32; };
    printf("%d\n", s.len() as i32);
    assert(f() == 2);
}
