static cnt: i32 = 0;

#drop
struct D{

}

impl Drop for D{
    func drop(*self){
        print("D is dropped\n");
        cnt += 1;
    }
}

struct A{
    d: D;
    d2: D;
}

enum E{
    V1(d: D),
    V2(a: A)
}

func struct_test(){
    let a = A{D{}, D{}};
    a.drop();
    assert(cnt == 2);
}

func enum_test(){
    let e = E::V1{D{}};
    e.drop();
    assert(cnt == 1);
    cnt = 0;

    let e2 = E::V2{A{D{}, D{}}};
    e2.drop();
    assert(cnt == 2);
}

func main(){
    struct_test();
    cnt = 0;

    enum_test();
    print("drop_test done\n");
}