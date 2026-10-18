//Macro slice 2: typed *value* parameters. An `Expr` parameter is a syntax slot
//(substituted at each use, so it writes through); any other declared type is a
//value: the argument is bound once at the top of the expansion with
//`let p: T = <arg>;` -- type-checked, evaluated exactly once -- and behaves
//like an ordinary local of the expansion (assigning to it does not touch the
//caller, and a move type argument is moved into it).
static calls = 0;

func next(): i32{
    calls = calls + 1;
    return 3;
}

macro bind(v: i32){
    //bound once: the argument runs once even though the body reads v twice
    assert(v == 3);
    assert(v == 3);
    assert(calls == 1);
}

//`Expr` slots and value parameters mix (doc/todo's `macro panic(e: Expr, s: String)`)
macro bump(e: Expr, by: i32){
    e = e + by;
}

//the parameter is bound under a fresh name, so sharing the caller's name is fine
macro local_only(y: i32){
    y = y + 1;
    assert(y == 6);
}

macro add(a: i32, b: i32){
    a + b
}

struct P{
    x: i32;
    y: i32;
}

macro sum_p(p: P){
    assert(p.x + p.y == 7);
}

func main(){
    bind!(next());
    assert(calls == 1);

    //an Expr slot writes through to the caller
    let x = 1;
    bump!(x, 2);
    assert(x == 3);

    //a value parameter does not
    let y = 5;
    local_only!(y);
    assert(y == 5);

    //expression macro with value parameters
    assert(add!(2, 3) == 5);
    assert(add!(x, y) == 8);

    //a move type is moved into the binding
    let p = P{3, 4};
    sum_p!(p);
}
