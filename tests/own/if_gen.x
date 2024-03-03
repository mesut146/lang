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
    assert check(1, id);
    //no drop
}

func if_var_if(c: bool, c2: bool, id: i32){
    if(c){
        let a = A{a: id};
        if(c2){
            send(a);
            assert check(1, id);
        }//gen drop in else
        assert check(1, id);
    }
    assert check(0, -1) || check(1, id);
}

func var_if_if(c: bool, c2: bool, id: i32){
    let a = A{a: id};
    if(c){
        if(c2){
            send(a);
            assert check(1, id);
        }//gen drop
        assert check(1, id);
    }//gen drop
    assert check(1, id);
}

func if1_redo(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
        a = A{a: id + 1};
        reset();
        assert check(0, -1);
    }
    //no drop bc reassign
    assert check(1, id);

    //valid
    a.a = 10;
    //drop at end
}


func main(){
    if1(true, 1);
    assert check(1, 1);
    reset();
    if1(false, 2);
    assert check(1, 2);
    reset();

    els(true, 3);
    assert check(1, 3);
    reset();
    els(false, 4);
    assert check(1, 4);
    reset();

    if_else(true, 5);
    assert check(1, 5);
    reset();
    if_else(false, 6);
    assert check(1, 6);
    reset();

    if_var_if(true, true, 7);
    assert check(1, 7);
    reset();
    if_var_if(true, false, 8);
    assert check(1, 8);
    reset();
    if_var_if(false, true, 9);
    assert check(0, -1);
    reset();

    var_if_if(true, true, 10);
    assert check(1, 10);
    reset();
    var_if_if(true, false, 11);
    assert check(1, 11);
    reset();
    var_if_if(false, true, 12);
    reset();

    if1_redo(true, 13);
    assert check(1, 13);
    reset();

}