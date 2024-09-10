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

func expr_struct(){
    let f = F::F2{val: B{aa: 10}};
    let x: B = match &f{
        F::F1(val) => {
            panic("");
        },
        F::F2(val) => {
            val
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
    expr_struct();
    printf("match done\n");
}