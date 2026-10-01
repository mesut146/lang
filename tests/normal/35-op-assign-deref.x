//regression: -=, *=, /= on dereferenced pointers used visit() (the
//loaded value) instead of get_lhs() (the address) as the store target
//and miscompiled (LLVM verification failure). += always worked.
func main(){
    let v = 100;
    let pv: i32* = &v;
    *pv += 1;
    assert(v == 101);
    *pv -= 1;
    assert(v == 100);
    *pv *= 2;
    assert(v == 200);
    *pv /= 4;
    assert(v == 50);
    //parenthesized lvalues must reach the inner deref, not visit()
    //the parens (same miscompile through a different path)
    (*pv) -= 1;
    assert(v == 49);
    //float through a pointer, all four ops (literals default to f32)
    let f = 2.0;
    let pf: f32* = &f;
    *pf += 0.5;
    assert(*pf == 2.5);
    *pf -= 0.5;
    assert(*pf == 2.0);
    *pf *= 3.0;
    assert(*pf == 6.0);
    *pf /= 2.0;
    assert(*pf == 3.0);
    print("deref op-assign done\n");
}
