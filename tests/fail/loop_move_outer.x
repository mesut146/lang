//A move of a value declared *outside* the loop is emitted once but runs on
//every iteration: the next iteration hands out (and frees) the same value
//again. Nothing leaves the loop here, so it must be rejected.
// should-fail: is moved inside a loop
import std/string

func send(s: String): i32{
    return s.len() as i32;
}

func main(){
    let s = String::new("x");
    let i = 0;
    while(i < 3){
        let n = send(s);
        i += 1;
    }
}
