//`continue` goes back to the loop head, so a move on that path is used again
//by the next iteration. The body's fall-through path ends in `i += 1` (no
//move), so this needs its own record: Own::do_continue notes the moved place
//and Own::end_scope reports it even when the body can also `return`.
// should-fail: is moved on a path that continues the loop
import std/string

func take(s: String): i32{
    return s.len() as i32;
}

func main(){
    let s = String::new("x");
    let i = 0;
    while(i < 3){
        if(i == 1){
            let n = take(s);
            continue;
        }
        i += 1;
    }
}
