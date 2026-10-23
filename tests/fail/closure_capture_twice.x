//Two closures cannot both take the same owning value: the first creation site
//moves it, so the second one reads a moved place.
// should-fail: use after move
import std/string

func main(){
    let s = String::new("hi");
    let f = ||: i32{ return s.len() as i32; };
    let g = ||: i32{ return s.len() as i32 + 1; };
    assert(f() + g() == 5);
}
