//Two traits can hand one type the same method name and the same signature.
//The impl method's identity has to include the trait: otherwise both impls
//mangle to one symbol (`P__tag_P$P_Fmt$P`), the second body is emitted as an
//unreachable block inside the first function, and every call -- qualified
//`A::tag`/`B::tag` and `{}`/`{::Trait}` alike -- runs whichever impl was
//declared first. Fmt is used as the printer so the two bodies are easy to
//compare.
trait A{
    func tag(self, f: Fmt*);
}

trait B{
    func tag(self, f: Fmt*);
}

struct P{
    x: i32;
}

impl A for P{
    func tag(self, f: Fmt*){
        f.print("A");
    }
}

impl B for P{
    func tag(self, f: Fmt*){
        f.print("B");
    }
}

func tag_a(p: P*): String{
    let f = Fmt::new();
    A::tag(p, &f);
    return f.unwrap();
}

func tag_b(p: P*): String{
    let f = Fmt::new();
    B::tag(p, &f);
    return f.unwrap();
}

func main(){
    let p = P{1};
    assert(tag_a(&p).eq("A"));
    assert(tag_b(&p).eq("B"));
    print("trait method symbols ok\n");
}
