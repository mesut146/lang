import own/common

struct F{
    a: A;
    b: A;
    c: i32;
}
impl F{
    func new(id1: i32, id2: i32): F{
        return F{
            A::new(id1),
            A::new(id2),
            111
        };
    }
}
func test(){
    let f = F::new(10, 20);
    f.a = A::new(15); //drop lhs
    check_ids(10);
    reset();
    f.c = 999;//nothing

    send(f.a);
    send(f.b);
    check_ids(15, 20);
}

struct G{
    f: F;
    a: A;
} 

func test_double(){

}

func main(){
    test();
    check_ids(15, 20);
}