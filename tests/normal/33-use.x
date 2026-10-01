mod M{
    struct A{ a: i32; }
    impl A{
        func get(self): i32 { return self.a; }
    }
    struct B{ b: i32; }
}
mod N{
    struct C{ c: i32; }
}

mod O{
    use M::A;
    func mk(): A{
        //use inside a module resolves file-wide
        return A{a: 4};
    }
}

use M::A;
use M::{B, A};
use N;

func mkc(): C{
    //C via `use N;` scope prefix
    return C{c: 1};
}

func main(){
    //bare A/B via aliases, C via scope prefix
    let a = A{a: 5};
    assert(a.get() == 5);
    let b = B{b: 6};
    assert(b.b == 6);
    assert(mkc().c == 1);
    //fully-qualified spelling still works alongside
    let a2 = M::A{a: 7};
    assert(a2.get() == 7);
    //use inside a module resolves file-wide
    assert(O::mk().a == 4);
    print("use done\n");
}
