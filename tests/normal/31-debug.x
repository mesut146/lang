//also compiled with -g in test.sh (debug smoke: struct+enum+match debug info)
struct Pt{
    x: i32;
    y: i32;
}
enum Shape{
    Dot(p: Pt),
    Empty,
}
func area(s: Shape): i32{
    match s{
        Shape::Dot(p) => return p.x * p.y,
        Shape::Empty => return 0,
    }
}
func main(){
    let p = Pt{x: 3, y: 4};
    assert(p.x == 3);
    assert(area(Shape::Dot{p: p}) == 12);
    assert(area(Shape::Empty) == 0);
    print("debug done\n");
}
