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

func val_test(){
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
    val_test();
    printf("match done\n");
}