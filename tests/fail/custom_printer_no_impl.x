// should-fail: no such method Hex::fmt
//A custom printer placeholder goes through ordinary method resolution, so a
//type that has no impl of the named trait is the same "no such method" error
//an explicit `Hex::fmt(x, f)` call would give.
trait Hex{
    func fmt(self, f: Fmt*);
}
struct P{
    x: i32;
}
func main(){
    let p = P{10};
    print("x={::Hex}\n", p);
}
