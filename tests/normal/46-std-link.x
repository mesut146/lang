//The standard library is linked by default: a plain compile (no -flags) can
//use String and the primitive Clone impls, which live in std. Before this it
//failed at link time unless the caller passed the archive through -flags:
//  undefined reference to `String__new_str'
//-nostd restores the bare link line (and -nolink never builds the archive).
//
//Pre-fix red: the link error above.

import std/string

//a derived Clone whose owner field goes through std's Clone (and Drop)
#derive(Clone)
struct Owned{
    name: String;
    n: i32;
}

func main(){
    let s = String::new("hello");
    assert(s.eq("hello"));

    //std's Clone for String
    let t = s.clone();
    assert(t.eq("hello"));

    //std's Clone for a primitive
    let n = 5;
    let m = n.clone();
    assert(m == 5);

    //the derive's field goes through std too
    let o = Owned{name: String::new("x"), n: 7};
    let o2 = o.clone();
    assert(o2.name.eq("x"));
    assert(o2.n == 7);

    print("std link done\n");
}
