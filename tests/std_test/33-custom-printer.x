//Custom printer (doc/todo): `{::TraitName}` inside a format string calls
//`TraitName::fmt(<arg>, &f)` instead of Display::fmt / Debug::debug, so a
//user trait with `func fmt(self, f: Fmt*)` prints a value its own way. The
//argument is positional like `{}` (it consumes the next call argument) and
//may be mixed with `{}`, `{:?}` and named args.
//
//P implements Display *and* the custom Hex: both give it a `fmt`, which is
//why the trait has to be part of the impl method's symbol (see
//34-trait-method-symbols.x). `{}` must reach Display::fmt and `{::Hex}`
//Hex::fmt no matter which impl is declared first.
trait Hex{
    func fmt(self, f: Fmt*);
}

#derive(Debug)
struct P{
    x: i32;
    y: i32;
}

//declared before Hex on purpose: the wrong impl used to win by order
impl Display for P{
    func fmt(self, f: Fmt*){
        f.print("display");
    }
}

impl Hex for P{
    func fmt(self, f: Fmt*){
        f.print("hex(");
        Debug::debug(&self.x, f);
        f.print(")");
    }
}

func main(){
    let p = P{10, 20};
    let n = 3;

    //format call, custom printer only
    let a = format("{::Hex}", p);
    assert(a.eq("hex(10)"));

    //mixed with Display, Debug and a named arg: arguments are consumed in
    //source order whatever the placeholder kind (a named placeholder takes
    //no call argument)
    let b = format!("{::Hex}/{}/{:?}/{n}", p, p, p);
    assert(b.eq("hex(10)/display/P{x: 10, y: 20}/3"));

    //two custom printers in one string
    let c = format!("{::Hex}{::Hex}", p, p);
    assert(c.eq("hex(10)hex(10)"));

    //the print call and the print! macro take the same format code
    print("[{::Hex}] [{:?}] [{}]\n", p, p, p);
    print!("[{::Hex}]\n", p);

    print("custom printer ok\n");
}
