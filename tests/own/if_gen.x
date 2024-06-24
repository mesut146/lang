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
    check_ids(id, id2);
}
func test2(){
    if_else_2_var(true, 10, 15);
    check_ids(10, 15);
    reset();

    if_else_2_var(false, 20, 25);
    check_ids(20, 25);
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
func if_else_redo1(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        check_ids(id);
        reset();
        a = A{a: id + 1};//no drop
        check_ids();
        //drop at end bc else moves
    }else{
        send(a);
        check_ids(id);
        reset();
    }//no drop in else
    //no drop at end
}

func test(){
    if_else_redo1(true, 7);
    check_ids(8);
    reset();
    if_else_redo1(false, 10);
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
    }
}

func var_if_if(c: bool, c2: bool, id: i32){
    let a = A{a: id};
    if(c){
        if(c2){
            send(a);
            check_ids(id);
        }//gen drop in else
        check_ids(id);
    }//gen drop in else
    check_ids(id);
}//no drop in end
func var_if_if_redo(c: bool, c2: bool, id: i32){
    let a = A{a: id};
    if(c){
        if(c2){
            send(a);
            check_ids(id);
            reset();
            a = A{a: id + 1};//no drop
            check_ids();
        }//no drop
        check_ids();
    }//no drop in else
    check_ids();
}//drop at end

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
    check_ids(0);
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
}


func main(){
    test1();
    test2();

    if_else_redo(true, 7);
    check_ids(8);
    reset();
    if_else_redo(false, 8);
    check_ids(10);
    reset();

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

    test();

    if_multi(true, false, 50);
    check_ids(50);
    reset();

    while_if_multi(true ,false, 100);
}

func if_multi(c1: bool, c2: bool, id: i32){
    let a = A::new(id);
    if(c1){
        send(a);
    }else if(c2){
        send(a);
    }else{
        let x = a.a;
    }
    check_ids(id);
}

func while_if_multi(c1: bool, c2: bool, id: i32){
    let i = 0;
    while(i < 1){
        let a = A::new(id);
        if(c1){
            send(a);
        }else if(c2){
            send(a);
        }else{
            let x = a.a;
        }
        check_ids(id);
        ++i;
    }
    check_ids(id);
}