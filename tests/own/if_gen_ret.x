import own/common

func if_ret(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
        reset();
        return;
    }//no drop in else bc return
    assert check(0, -1);
    //valid bc return
    let tmp = a.a;
    //drop at end
}

func if_var_if_ret(c: bool, c2: bool, id: i32){
    if(c){
        let a = A{a: id};
        if(c2){
            send(a);
            assert check(1, id);
            return;
        }
        assert check(0, -1);
    }//drop in end
}

func main(){
    if_ret(true, 5);
    reset();
    if_ret(false, 10);
    assert check(1, 10);
    reset();

    if_var_if_ret(true, true, 15);
    assert check(1, 15);
    reset();
    if_var_if_ret(true, false, 20);
    assert check(1, 20);
    reset();
    if_var_if_ret(false, true, 25);
    assert check(0, -1);
    reset();

}