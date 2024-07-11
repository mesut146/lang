import own/common

func if_only(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        check_ids(id);
    }else{
        check_ids();
        //a.drop()
    }
    check_ids(id);
    //no drop
}
func else_only(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        check_ids();
        //a.drop()
    }else{
        send(a);
        check_ids(id);
    }
    check_ids(id);
}
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
func test1(){
    if_only(true, 1);
    check_ids(1);
    reset();
    if_only(false, 2);
    check_ids(2);
    reset();

    else_only(true, 3);
    check_ids(3);
    reset();
    else_only(false, 4);
    check_ids(4);
    reset();
}

func if_else_2_var(c: bool, id: i32, id2: i32){
    let a = A{a: id};
    let b = A{a: id2};
    if(c){
        send(a);
        check_ids(id);
        //b.drop();
    }else{
        send(b);
        check_ids(id2);
        //a.drop();
    }
}
func test2(){
    if_else_2_var(true, 10, 15);
    check_ids(10, 15);
    reset();

    if_else_2_var(false, 20, 25);
    check_ids(25, 20);
    reset();
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

func if_var_if(c: bool, c2: bool, id: i32){
    if(c){
        let a = A{a: id};
        if(c2){
            send(a);
            check_ids(id);
        }//gen drop in else
        check_ids(id);
    }
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

func var_if_if(c: bool, c2: bool, id: i32){
    let a = A{a: id};
    if(c){
        if(c2){
            send(a);
            check_ids(id);
        }//a.drop() in else
        check_ids(id);
    }//a.drop() in else
    check_ids(id);
}//no drop in end
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
    test1();
    test2();
    test3();

    if_var_if(true, true, 7);
    check_ids(7);
    reset();
    if_var_if(true, false, 8);
    check_ids(8);
    reset();
    if_var_if(false, true, 9);
    check_ids();
    reset();

    if_var_if_redo(true, true, 10);
    check_ids(11);
    reset();
    if_var_if_redo(true, false, 12);
    check_ids(12);
    reset();
    if_var_if_redo(false, true, 13);
    check_ids();
    reset();

    var_if_if(true, true, 10);
    check_ids(10);
    reset();
    var_if_if(true, false, 11);
    check_ids(11);
    reset();
    var_if_if(false, true, 12);
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

