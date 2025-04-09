struct A{
    a: i64;
    b: i64;
}

struct B{
    aa: i64;
}

enum E: B{
    E1,
    E2(val: i32, a: A),
    E3(val: i32)
}

enum F{
    F1(val: A),
    F2(val: B),
}

func expr_i32(){
    let e = E::E2{.B{aa: 12345}, val: 10, a: A{a: 20, b: 30}};
    let x: i32 = match &e {
        E::E1 => 100,
        E::E2(val, a) => {
            200
        },
        E::E3(val) => {
            300
        }
    };
    assert(x == 200);
}

func expr_i32_omit(){
    let e = E::E2{.B{aa: 12345}, val: 10, a: A{a: 20, b: 30}};
    let x: i32 = match &e {
        E::E1 => 100,
        E2(val, a) => {
            200
        },
        E3(val) => {
            300
        }
    };
    assert(x == 200);
}

func expr_i32_2(){
    let e = E::E2{.B{aa: 12345}, val: 10, a: A{a: 20, b: 30}};
    let x: i64 = match &e {
        E::E1 => 100i64,
        E::E2(val, a) => {
            a.b
        },
        E::E3(val) => {
            300i64
        }
    };
    assert(x == 30);
}

func expr_i32_ret(): i64{
    let e = E::E2{.B{aa: 12345}, val: 10, a: A{a: 20, b: 30}};
    match &e {
        E::E1 => 100i64,
        E::E2(val, a) => {
            a.b
        },
        E::E3(val) => {
            300i64
        }
    }
}

func expr_struct(){
    let f = F::F2{val: B{aa: 10}};
    let x: B = match &f{
        F::F1(val) => {
            panic("");
        },
        F::F2(b) => {
            b
        }
    };
    assert(x.aa == 10);

    let f2 = F::F1{val: A{a: 20, b: 30}};
    let x2: A = match &f2{
        F::F1(val) => {
            val
        },
        F::F2(val) => {
            panic("")
        }
    };
    assert(x2.a == 20 && x2.b == 30);
}

func getb(): bool{ return true; }
func def_test(){
    let f1 = F::F1{val: A{a: 20, b: 30}};
    let res1 = match &f1{
        F::F1(val*) => 123,
        _=> panic("def")
    };
    assert(res1 == 123);
    
    let f2 = F::F1{val: A{a: 200, b: 300}};
    let res2 = match &f2{
        F::F2(val*) => 124,
        _=> 234
    };
    assert(res2 == 234);
}

func cast(){
    let f = F::F2{val: B{aa: 10}};
    let b: bool = match &f{
        F::F2(val*) => getb() == getb(),
        F::F1(a*)=> /*getb()*/true
    };
}

func jump(): bool{
    let f = F::F2{val: B{aa: 10}};
    match &f{
        F::F1(val*) => { return true; },
        F::F2(val*) => return false,
    }
}

func main(){
    let e = E::E2{.B{aa: 12345}, val: 10, a: A{a: 20, b: 30}};
    match &e {
        E::E1 => print("E1\n"),
        E::E2(val, a) => {
            printf("E2 %d %d,%d\n", val, a.a, a.b);
        },
        E::E3(val) => {
            printf("E3\n");
        }
    }
    expr_i32();
    expr_i32_omit();
    expr_i32_2();
    expr_struct();
    def_test();
    printf("match done\n");
}