struct A{
    a: i32;
    b: str;
}

impl Debug for A{
    func debug(self, f: Fmt*){
        print("A::debug\n");
        f.print("debug()");
    }
}
impl Display for A{
    func fmt(self, f: Fmt*){
        print("A::fmt\n");
        f.print("fmt()");
    }
}

func main(){
    let a = A{10, "aa"};
    let s = format("dsp={} dbg={:?}\n", a, a);
    print("{}", s);
    s.drop();
}