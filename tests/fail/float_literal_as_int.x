//A float literal cannot be used where an integer type is declared. This used to
//panic the compiler inside the literal-coercion branch (i64::parse("2.5")),
//not report an error.
// should-fail: 2.5 is a float literal, not i32
func main(){
    let x: i32 = 2.5;
    assert(x == 2);
}
