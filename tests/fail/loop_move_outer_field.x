//A *field* moved in the loop body is the same bug as a whole value: the
//second iteration hands the callee the same String again. The whole-var
//write before the loop must not excuse it (Own::check_loop_moves only lets a
//write made *in the body* cover the field marks; std/hashmap's rehash
//reassigns `node` at the top of the body before moving its fields, and that
//one is fine).
// should-fail: is moved inside a loop
import std/string

struct H{
    s: String;
}

func take(s: String): i32{
    return s.len() as i32;
}

func mk(): H{
    return H{s: String::new("y")};
}

func main(){
    let h = H{s: String::new("x")};
    h = mk();
    let i = 0;
    while(i < 3){
        let n = take(h.s);
        i += 1;
    }
}
