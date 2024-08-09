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

func main(){
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