//helper unit for the cross-unit macro test: its items are only reachable from
//main.x *through* the body of a macro defined in macros.x
struct H{
    n: i32;
    m: i32;
}

func h_seven(): i32{
    return 7;
}
