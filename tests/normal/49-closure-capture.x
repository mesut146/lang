//Capturing lambdas (`|...|` closures), phase A of doc/closures.txt: a lambda
//body may read an enclosing local. The values are copied *by value* into a
//heap closure object at the creation site (`{ fn, captured... }`, see
//closure_payload_type in compiler_helper.x) and handed to the generated method
//as extra arguments on every call; the value itself is the object pointer and
//the closure's drop frees it.
//Phase A captures plain values only (integers, bools, floats and aggregates of
//them); capturing an owning value and capturing through an inner lambda are
//loud errors (tests/fail/closure_capture_owning.x,
//tests/fail/closure_capture_nested.x).
//
//Pre-fix red: "captured params not supported yet" (resolver.x visit_lambda).

struct P{ a: i32; b: i32; }

static counter: i32 = 5;

func apply<T>(fp: T, v: i32): i32{
    return fp(v);
}

//a lambda capturing a parameter of the enclosing function
func scaled(k: i32): i32{
    let lm = |v: i32|: i32{ return v * k; };
    return lm(7);
}

func main(){
    //by value: the closure keeps the value it was created with, and the
    //caller's variable stays usable (no move for a plain type)
    let base = 40;
    let add = |v: i32|: i32{
        return v + base;
    };
    base += 1;
    assert(add(2) == 42);
    assert(base == 41);

    //two closures capturing different values are independent
    let x = 1;
    let y = 2;
    let fx = |v: i32|: i32{ return v + x; };
    let fy = |v: i32|: i32{ return v + y; };
    assert(fx(10) == 11);
    assert(fy(10) == 12);

    //a capturing closure value can be moved and called through a generic
    let moved = fx;
    assert(apply(moved, 5) == 6);

    //aggregate capture (a plain struct), and a nullary capturing lambda
    let p = P{a: 1, b: 2};
    let sum = ||: i32{ return p.a + p.b; };
    assert(sum() == 3);

    //a global is not captured: the body reads it when it runs
    let g = ||: i32{ return counter; };
    counter = 9;
    assert(g() == 9);

    //captures of different widths in one closure: a bool, a str (a 16-byte
    //slice) and an f64 in one object. A wrong copy width or a shared node id
    //between the capture reads shows up here (the first capture's type used to
    //be copied for every field).
    let flag = true;
    let msg = "boom";
    let k = 2.5;
    let n = 7;
    let wide = ||: i32{
        assert(flag);
        assert(msg.len() == 4);
        assert(k > 2.0);
        assert(n == 7);
        printf("wide %d %d %d\n", 1, msg.len() as i32, n);
        return 1;
    };
    assert(wide() == 1);

    //one closure per loop iteration, dropped per iteration
    let total = 0;
    for(let i = 0;i < 3;++i){
        let f = |v: i32|: i32{ return v + i; };
        total += f(1);
    }
    assert(total == 6);

    assert(scaled(3) == 21);
}
