import own/common

func else_only_redo(c: bool, id: i32){
    let a = A{a: id};
    send(a);
    check_ids(id);
    reset();
    //already moved
    if(c){
        //no drop
        //todo; a is none by else which is false, ignore else
    }else{
        a = A::new(id + 1);//drop
        check_ids();
        send(a);
        check_ids(id + 1);
        reset();
    }
    check_ids();
}
func if_else_redo(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        check_ids(id);
        reset();
        a = A{a: id + 1};//no drop
        check_ids();
    }else{
        send(a);
        check_ids(id);
        reset();
        a = A{a: id + 2};//no drop
        check_ids();
    }
    //a.drop
}
func if_else_redo2(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        check_ids(id);
        reset();
        a = A{a: id + 1};//no drop
        check_ids();
        //a.drop() bc else moves
    }else{
        send(a);
        check_ids(id);
        reset();
    }//no drop in else
    //no drop at end
}

func test3(){
    if_else_redo(true, 7);
    check_ids(8);
    reset();
    if_else_redo(false, 9);
    check_ids(11);
    reset();

    if_else_redo2(true, 70);
    check_ids(71);
    reset();
    if_else_redo2(false, 100);
    check_ids();
}

func if_var_if_redo(c: bool, c2: bool, id: i32){
    if(c){
        let a = A{a: id};
        if(c2){
            send(a);
            check_ids(id);
            reset();
            a = A{a: id + 1};//no drop
            check_ids();
        }
        check_ids();
    }//a.drop()
}

func var_if_if_redo(c: bool, c2: bool, id: i32){
    let a = A{a: id};
    let new_id = id;
    if(c){
        if(c2){
            send(a);
            check_ids(id);
            reset();
            a = A{a: id + 1};//no drop
            check_ids();
            new_id = id + 1;
        }//no drop
        check_ids();
    }//no drop in else
    check_ids();
    a.check(new_id);
}//a.drop()

func if1_redo(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        check_ids(id);
        a = A{a: id + 1};//no drop
        reset();
        check_ids();
    }
    //no drop bc reassign
    check_ids();
    //valid
    let tmp = a.a;
    //drop at end
}//a.drop()
func els_redo(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        //no drop
    }
    else{
        send(a);
        check_ids(id);
        reset();
        a = A{a: id + 1};//no drop
        check_ids();
    }
    //no drop bc reassign
    check_ids();
    //valid
    let tmp = a.a;
    //drop at end
}//a.drop()

func main(){
    test3();

    if_var_if_redo(true, true, 10);
    check_ids(11);
    reset();
    if_var_if_redo(true, false, 12);
    check_ids(12);
    reset();
    if_var_if_redo(false, true, 13);
    check_ids();
    reset();

    var_if_if_redo(true, true, 13);
    check_ids(14);
    reset();
    var_if_if_redo(true, false, 14);
    check_ids(14);
    reset();

    if1_redo(true, 13);
    check_ids(14);
    reset();
    if1_redo(false, 15);
    check_ids(15);
    reset();

    els_redo(true, 17);
    check_ids(17);
    reset();
    els_redo(false, 20);
    check_ids(21);
    reset();
}