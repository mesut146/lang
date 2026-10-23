import own/common

//Capturing lambdas, phase B (doc/closures.txt section 9): an owning captured
//value moves into the closure object at the creation site and is dropped
//exactly once, by the closure's own drop. Uses:
//- a closure that is called: the captured owner must not be dropped per call;
//- a closure that is never called: the object still drops it;
//- a closure passed to a generic, which drops it when its parameter dies;
//- one closure per loop iteration;
//- a struct-with-owner capture (the object's drop reaches the field's glue);
//- a closure dropped at the end of a nested scope.
//
//Pre-fix red: capturing an owning value was rejected ("capturing an owning
//value is not supported yet"), so this file did not compile at all.

struct Holder{
    a: A;
}

func apply<T>(fp: T, v: i32): i32{
    return fp(v);
}

func called(){
    let a = A::new(1);
    let f = ||: i32{ return a.a; };
    assert(f() == 1);
    assert(f() == 1);
}

func never_called(){
    let a = A::new(2);
    let f = ||: i32{ return a.a; };
}

func through_generic(){
    let a = A::new(3);
    let f = |v: i32|: i32{ return v + a.a; };
    assert(apply(f, 10) == 13);
}

func per_iteration(){
    let total = 0;
    for(let i = 0;i < 3;++i){
        let a = A::new(i);
        let f = ||: i32{ return a.a; };
        total += f();
    }
    assert(total == 3);
}

func struct_field(){
    let h = Holder{a: A::new(4)};
    let f = ||: i32{ return h.a.a; };
    assert(f() == 4);
}

//an owning receiver: `self` is a value like any other, so the closure keeps
//it and the closure's drop drops it (the method's end-of-scope drop is
//suppressed by the move)
struct Wrap{
    a: A;
}

impl Wrap{
    func value(self): i32{
        let f = ||: i32{ return self.a.a; };
        return f();
    }
}

func owning_self(){
    let w = Wrap{a: A::new(7)};
    assert(w.value() == 7);
}

func main(){
    reset();
    called();
    check_ids(1);

    reset();
    never_called();
    check_ids(2);

    reset();
    through_generic();
    check_ids(3);

    reset();
    per_iteration();
    check_ids(0, 1, 2);

    reset();
    struct_field();
    check_ids(4);

    reset();
    owning_self();
    check_ids(7);
    print("closure owning drop done\n");
}
