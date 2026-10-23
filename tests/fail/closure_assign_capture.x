//Writing a captured owning value would leak: the generated method does not
//drop the borrowed field, and the object's drop still frees the old value.
//No `mut` capture in v1 (doc/closures.txt section 9).
// should-fail: cannot assign to a captured value
import std/string

func main(){
    let s = String::new("hi");
    let f = ||: void{ s = String::new("bye"); };
    f();
}
