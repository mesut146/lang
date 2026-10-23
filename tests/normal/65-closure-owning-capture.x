//Capturing lambdas, phase B (doc/closures.txt section 9): an owning value
//moves into the closure object at the creation site, the closure's own drop
//frees it, and the generated method only *borrows* the object's fields -- it
//neither drops them at return nor lets the body move them out. Nested capture
//of plain values and `self` capture work the same way.
//
//Pre-fix red: "capturing an owning value is not supported yet",
//"capturing through a lambda is not supported yet".
import std/string
import std/list

struct P{
    t: String;
    n: i32;
}

struct Counter{
    n: i32;
}

impl Counter{
    //`self` is captured like any other value (plain here, see the owning
    //receiver in tests/own/33closure_owning.x)
    func add_to(self, d: i32): i32{
        let f = |v: i32|: i32{ return v + self.n; };
        return f(d);
    }
}

func apply<T>(fp: T, v: i32): i32{
    return fp(v);
}

func takes_owner(k: String): i32{
    let f = ||: i32{ return k.len() as i32; };
    return f();
}

func main(){
    //an owning capture: the body reads the closure's value on every call
    let s = String::new("hello");
    let f = ||: i32{ return s.len() as i32; };
    assert(f() == 5);
    assert(f() == 5);

    //a List capture, mutated through the body: the body works on the
    //closure object's field (one owner, no copy reallocating behind it), so
    //the mutation lands in the closure's list and persists across calls
    let l = List<i32>::new();
    l.add(1);
    let g = ||: i32{
        l.add(41);
        return l.len() as i32;
    };
    assert(g() == 2);
    assert(g() == 3);

    //two owners in one closure: each gets its own payload slot (and its own
    //node id; a shared id made the ownership engine confuse the two)
    let a = String::new("ab");
    let b = String::new("cde");
    let h = ||: i32{ return a.len() as i32 + b.len() as i32; };
    assert(h() == 5);

    //an owner nested in a struct
    let p = P{t: String::new("hi"), n: 2};
    let s2 = ||: i32{ return p.t.len() as i32 + p.n; };
    assert(s2() == 4);

    //a capturing closure through a generic parameter (T = the closure type)
    let q = String::new("xyz");
    let k = |v: i32|: i32{ return v + q.len() as i32; };
    assert(apply(k, 1) == 4);

    //nested closures: the inner one captures through the outer one -- both
    //the outer lambda's capture (x) and the outer lambda's own parameter (v)
    let x = 3;
    let outer = |v: i32|: i32{
        let inner = |w: i32|: i32{ return w + x; };
        let inner2 = |w: i32|: i32{ return w + v; };
        return inner(v) + inner2(1);
    };
    assert(outer(4) == 12);

    //capturing `self`
    let c = Counter{n: 5};
    assert(c.add_to(1) == 6);

    //capturing an owning parameter of the enclosing function
    assert(takes_owner(String::new("abcd")) == 4);

    //one closure (with an owner) per loop iteration
    let total = 0;
    for(let i = 0;i < 3;++i){
        let e = String::new("xy");
        let per = ||: i32{ return e.len() as i32 + i; };
        total += per();
    }
    assert(total == 9);
    printf("closures phase B ok\n");
}
