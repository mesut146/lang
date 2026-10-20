//A float literal coerced to a declared float type: `let k: f64 = 2.5;`, a
//f64 call argument, a f64 struct field and a negative literal.
//The literal-coercion branch in MethodResolver::is_compatible ran the integer
//range check (`i64::parse(<literal text>)`) for every literal, so the text of a
//float literal was parsed as an integer.
//
//Pre-fix red: `let k: f64 = 2.5;` aborted the compiler with
//  unwrap on empty Result, err='invalid digit '.' at pos 1'
//(`: f32` worked because the argument and target types are equal there, so the
//branch is skipped; `2.5 as f64` also worked around it).

struct P{ v: f64; }

func take(v: f64): f64{
    return v * 2.0;
}

func main(){
    let k: f64 = 2.5;
    assert(k == 2.5);
    let neg: f64 = -2.5;
    assert(neg < 0.0);
    //an integer literal into a float type keeps working
    let i: f64 = 2;
    assert(i == 2.0);
    //the same coercion at a call argument
    assert(take(1.5) == 3.0);
    //and in a struct literal field
    let p = P{v: 4.5};
    assert(p.v == 4.5);
    //f32 keeps its old behaviour
    let f: f32 = 2.5;
    assert(f == 2.5);
}
