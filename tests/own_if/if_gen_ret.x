import own/common

func if_ret(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        check_ids(id);
        reset();
        return;
    }//no drop in else bc return
    check_ids();
    //valid bc return
    a.check(id);
    //drop at end
}

func if_var_if_ret(c: bool, c2: bool, id: i32){
    if(c){
        let a = A{a: id};
        if(c2){
            send(a);
            check_ids(id);
            return;
        }
        check_ids();
    }//drop in end
}

func main(){
    if_ret(true, 5);
    reset();
    if_ret(false, 10);
    check_ids(10);
    reset();

    if_var_if_ret(true, true, 15);
    check_ids(15);
    reset();
    if_var_if_ret(true, false, 20);
    check_ids(20);
    reset();
    if_var_if_ret(false, true, 25);
    check_ids();
    reset();

}