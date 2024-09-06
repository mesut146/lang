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
    printf("match done\n");
}