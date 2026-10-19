//A unit enum variant prints like a type path but is a runtime value: calling a
//method on it takes its address. AllocHelper skipped *every* Expr::Type call
//scope (right for `M::A::method`, `Trait::method(x)`, `m::f()` -- those are not
//runtime values), so a unit-variant receiver never got an alloc and the emitter
//died with "get_alloc() not set"; with that fixed alone the operand lookup then
//reported "eval_operand Kind::Empty".
//
//Pre-fix red: `method Kind::Empty::is_empty() not found from candidates /
//arg size mismatched 0 vs 1` at the assert below. Two bugs stack up:
//assert builds its message by printing the condition and parsing it back, and
//the printer rendered a value receiver as `Kind::Empty::is_empty()` -- a
//static call (debug_call in printer.x); once that is fixed the `clone()` line
//is the next failure, `get_alloc() not set` at emission (the alloc helper
//skipped every Expr::Type call scope, and eval_operand had no operand for a
//unit variant).

#derive(Clone)
enum Kind{
    Empty,
    Data{v: i32}
}

impl Kind{
    func is_empty(self): bool{
        if let Kind::Empty = self{
            return true;
        }
        return false;
    }
}

struct Point{
    x: i32;
}

impl Point{
    func new(x: i32): Point{
        return Point{x: x};
    }
    func get(self): i32{
        return self.x;
    }
}

mod m{
    func twice(v: i32): i32{
        return v * 2;
    }
}

func main(){
    //the observed case: clone a unit-variant literal
    let a = Kind::Empty.clone();
    assert(a.is_empty());
    let b = Kind::Data{v: 3}.clone();
    assert(!b.is_empty());

    //unit variant literal as the receiver of a user method (the same bug,
    //here through assert's print-and-reparse)
    assert(Kind::Empty.is_empty());
    //a payload-variant literal receiver always worked: keep it as a guard
    assert(!Kind::Data{v: 5}.is_empty());

    //type scopes keep their behaviour: a static call on a type and a module
    //function are not runtime values
    assert(Point::new(4).get() == 4);
    assert(m::twice(6) == 12);

    print("variant receiver done\n");
}
