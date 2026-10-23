//The creation site emits one move per iteration: capturing an owner that is
//declared *outside* the loop would hand the same allocation to the first
//iteration's closure and then to the second, which frees it again. A closure
//created per iteration that captures an owner *declared in the body* is fine
//(tests/normal/65-closure-owning-capture.x, last block).
// should-fail: capturing an owning value declared outside the loop
import std/string

func main(){
    let s = String::new("x");
    for(let i = 0;i < 3;++i){
        let f = ||: i32{ return s.len() as i32; };
        assert(f() == 1);
    }
}
