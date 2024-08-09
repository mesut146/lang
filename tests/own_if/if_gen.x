import own/common

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


func main(){
    test2();

    if_var_if(true, true, 7);
    check_ids(7);
    reset();
    if_var_if(true, false, 8);
    check_ids(8);
    reset();
    if_var_if(false, true, 9);
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
}

