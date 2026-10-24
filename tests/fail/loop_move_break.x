//A `break` path that moves an outer value: after the loop x cannot tell
//whether the value is still owned (the loop may never run, or may take the
//fall-through path) and x has no drop flags, so a drop there would either
//leak or free twice. Same call as an else-only move: reject it. A move before
//an unconditional `break` is fine (tests/own/34loop_move.x).
// should-fail: is moved on a path that breaks out of the loop
import std/string

func take(s: String): i32{
    return s.len() as i32;
}

func main(){
    let s = String::new("x");
    let i = 0;
    while(i < 5){
        if(i == 1){
            let n = take(s);
            break;
        }
        i += 1;
    }
    printf("after %d\n", s.len() as i32);
}
