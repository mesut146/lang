struct A{
    a: i64;
    b: i64;
}

enum E{
    E1,
    E2(val: i32, a: A),
    E3(val: i32)
}


func main(){
    let e = E::E1;
    match &e {
        E::E1 => print("E1\n"),
        E::E2(val, a) => {
            print("E2\n");
        },
        E::E3(val) => {
            print("E3\n");
        }
    }
    print("match done\n");
}