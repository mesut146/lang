import own/common

func normal(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        let b = A{a: id + 1};
        return;//a.drop(), b.drop()
    }
    //a.drop
}
func test_normal(){
    normal(true, 1);
    assert check_ids([1,2][0..2]);
    reset();
    normal(false, 3);
    assert check(1, 3);
    reset();
}

func move_inner(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        let b = A{a: id + 1};
        send(b);
        assert check(1, id + 1);
        reset();
        return;//a.drop(), b moved
    }
    //a.drop
}
func test_move_inner(){
    move_inner(true, 4);
    assert check(1, 4);
    reset();
    move_inner(false, 5);
    assert check(1, 5);
    reset();
}

func move_outer(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        let b = A{a: id + 1};
        send(a);
        assert check(1, id);
        reset();
        return;//b.drop(), a moved
    }
    //a.drop, bc return
}
func test_move_outer(){
    move_outer(true, 7);
    assert check(1, 7 + 1);
    reset();
    move_outer(false, 9);
    assert check(1, 9);
}

func main(){
    test_normal();
    test_move_inner();
    test_move_outer();
}