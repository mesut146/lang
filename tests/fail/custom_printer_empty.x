// should-fail: invalid format custom printer
//`{::}` names no printer. Before this was diagnosed the placeholder was taken
//as a named-argument expression and the parser failed on the leading `::`
//("invalid expr Token{value: '::'}"), which is what the pre-fix runs show.
struct P{
    x: i32;
}
func main(){
    let p = P{10};
    print("x={::}\n", p);
}
