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
func mut_field(){
    let f = F::new(10, 20);
    f.a = A::new(15); //drop lhs
    check_ids(10);
    reset();
    f.c = 999;//nothing

    send(f.a);
    send(f.b);
    check_ids(15, 20);
    //dont drop f(all fields moved)
}

func redo(id: i32, id2: i32, c1: bool){
    let f = F::new(id, id2);
    send(f.a);
    if(c1){
        f.a = A::new(id + 1);
    }else{
        f.a = A::new(id + 2);
    }
    //f.drop()
}

struct G{
    f: F;
    a: A;
} 

func test_double(){

}

func main(){
    mut_field();
    check_ids(15, 20);
    reset();

    redo(40, 50, true);
    check_ids(40, 41, 50);
    reset();

    redo(60, 70, false);
    check_ids(60, 62, 70);
    reset();

}