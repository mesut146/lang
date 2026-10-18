//Macro slice 3b: macros follow the language's module rules. A macro declared
//inside a `mod` is a module item like any other: a bare `name!` reaches only
//top-level macros, `m::name!` (or `a::b::name!`) matches the module it was
//declared in, and `use m;` / `use m::{name}` bring a module's macros into bare
//scope.
macro bump(e: Expr, by: i32){
    e = e + by;
}

mod helpers{
    macro double_it(v: Expr){
        v = v * 2;
    }
    mod more{
        macro add_one(v: Expr){
            v = v + 1;
        }
    }
}

mod tools{
    macro triple_it(v: Expr){
        v = v * 3;
    }
}

use tools;

use helpers::{double_it};

func main(){
    let a = 1;

    //a top-level macro is called bare
    bump!(a, 1);
    assert(a == 2);

    //a module macro through its path
    helpers::double_it!(a);
    assert(a == 4);

    //nested module path
    helpers::more::add_one!(a);
    assert(a == 5);

    //`use helpers::{double_it}` puts that macro in bare scope
    double_it!(a);
    assert(a == 10);

    //`use tools;` does the same for every macro of the module
    triple_it!(a);
    assert(a == 30);
}
