import own/common

func normal(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        let b = A::new(id + 1);
        return;//b.drop(), a.drop()
    }
    //a.drop
}
func test_normal(){
    normal(true, 1);
    check_ids(2, 1);
    reset();
    
    normal(false, 3);
    check_ids(3);
    reset();
}

func move_inner(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        let b = A{a: id + 1};
        send(b);
        check_ids(id + 1);
        return;//a.drop()
    }
    //a.drop
}
func test_move_inner(){
    move_inner(true, 4);
    check_ids(5, 4);
    reset();

    move_inner(false, 10);
    check_ids(10);
    reset();
}

func move_outer(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        let b = A{a: id + 1};
        send(a);
        return;//b.drop(), a moved
    }
    //a.drop, bc return
}
func test_move_outer(){
    move_outer(true, 20);
    check_ids(20, 20 + 1);
    reset();
    move_outer(false, 25);
    check_ids(25);
}

func main(){
    test_normal();
    test_move_inner();
    test_move_outer();
}