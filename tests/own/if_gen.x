import own/common


func if1(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
    }
    //if one branch drops, other must drop too
    //this else block compiler generated
    // else{
    //     a.drop();
    // }
    assert check(1, id);
}

/*func if1_level2(c: bool, c2: bool, id: i32){
    if(c){
        let a = A{a: id};
        if(c2){
            send(a);
            assert check(1, id);
        }//gen drop
        assert check(1, id);
    }
}

func if1_level22(c: bool, c2: bool, id: i32){
    let a = A{a: id};
    if(c){
        if(c2){
            send(a);
            assert check(1, id);
        }//gen drop
        assert check(1, id);
    }//gen drop
}

func if1_redo(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
        a = A{a: id + 1};
    }
    //no drop bc reassign
    assert check(1, id);

    //valid
    a.a = 10;
}*/

func els(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        //generated
        //a.drop()
    }else{
        send(a);
        assert check(1, id);
    }
    assert check(1, id);
    //invalid
    //a.a = 10;
}

func if_else(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
    }else{
        assert check(0, -1);
        //a.drop()
    }
    print("after if\n");
    //no drop
    assert check(1, id);
}

func main(){
    if1(true, 5);
    assert check(1, 5);
    reset();
    if1(false, 10);
    assert check(1, 10);

    reset();

    els(true, 15);
    assert check(1, 15);
    reset();
    els(false, 20);
    assert check(1, 20);

    reset();

    if_else(true, 1);
    assert check(1, 1);
    reset();
    if_else(false, 2);
    assert check(1, 2);
}