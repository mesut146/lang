import own/common


func if1(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
    }//drop in else
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
func if_else_redo(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
        reset();
        a = A{a: id + 1};//no drop
        assert check(0, -1);
    }else{
        send(a);
        assert check(1, id);
        reset();
        a = A{a: id + 2};//no drop
        assert check(0, -1);
    }
    //a.drop
}
func if_else_redo1(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
        reset();
        a = A{a: id + 1};//no drop
        assert check(0, -1);
        //drop at end bc else moves
    }else{
        send(a);
        assert check(1, id);
        reset();
    }//no drop in else
    //no drop at end
}

func test(){
    if_else_redo1(true, 7);
    assert check(1, 8);
    reset();
    if_else_redo1(false, 10);
    assert check(0, -1);
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
func if_var_if_redo(c: bool, c2: bool, id: i32){
    if(c){
        let a = A{a: id};
        if(c2){
            send(a);
            assert check(1, id);
            reset();
            a = A{a: id + 1};//no drop
            assert check(0, -1);
        }
        assert check(0, -1);
    }
}

func var_if_if(c: bool, c2: bool, id: i32){
    let a = A{a: id};
    if(c){
        if(c2){
            send(a);
            assert check(1, id);
        }//gen drop in else
        assert check(1, id);
    }//gen drop in else
    assert check(1, id);
}//no drop in end
func var_if_if_redo(c: bool, c2: bool, id: i32){
    let a = A{a: id};
    if(c){
        if(c2){
            send(a);
            assert check(1, id);
            reset();
            a = A{a: id + 1};//no drop
            assert check(0, -1);
        }//no drop
        assert check(0, -1);
    }//no drop in else
    assert check(0, -1);
}//drop at end

func if1_redo(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
        a = A{a: id + 1};//no drop
        reset();
        assert check(0, -1);
    }
    //no drop bc reassign
    assert check(0, -1);
    //valid
    let tmp = a.a;
    //drop at end
}
func els_redo(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        //no drop
    }
    else{
        send(a);
        assert check(1, id);
        a = A{a: id + 1};//no drop
        reset();
        assert check(0, -1);
    }
    //no drop bc reassign
    assert check(0, -1);
    //valid
    let tmp = a.a;
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

    if_else_redo(true, 7);
    assert check(1, 8);
    reset();
    if_else_redo(false, 8);
    assert check(1, 10);
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

    if_var_if_redo(true, true, 10);
    assert check(1, 11);
    reset();
    if_var_if_redo(true, false, 12);
    assert check(1, 12);
    reset();
    if_var_if_redo(false, true, 13);
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

    var_if_if_redo(true, true, 13);
    assert check(1, 14);
    reset();
    var_if_if_redo(true, false, 14);
    assert check(1, 14);
    reset();

    if1_redo(true, 13);
    assert check(1, 14);
    reset();
    if1_redo(false, 15);
    assert check(1, 15);
    reset();

    els_redo(true, 17);
    assert check(1, 17);
    reset();
    els_redo(false, 20);
    assert check(1, 21);
    reset();

    test();
}