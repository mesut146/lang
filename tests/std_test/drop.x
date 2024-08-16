static cnt: i32 = 0;

#drop
struct D{
    id: i32;
}

impl Drop for D{
    func drop(*self){
        print("D::drop() {}\n", self.id);
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
    let a = A{D{10}, D{20}};
    a.drop();
    assert(cnt == 2);
}

func enum_test(){
    let e = E::V1{D{30}};
    e.drop();
    assert(cnt == 1);
    cnt = 0;

    let e2 = E::V2{A{D{40}, D{50}}};
    e2.drop();
    assert(cnt == 2);
}

func main(){
    struct_test();
    cnt = 0;

    enum_test();
    print("drop_test done\n");
}