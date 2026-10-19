// should-fail: resolves to a local at this call site
//A free body name is resolved at the call site, so this macro used to read the
//caller's `v` silently (the hygiene work only renames names the body itself
//declares). Reading a caller value must be explicit: pass it as a parameter.
macro show() {
    print("{}\n", v);
}

func main(){
    let v = 1;
    show!();
}
