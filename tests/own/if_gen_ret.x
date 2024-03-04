import own/common

func if_ret(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
        return;
        //panic("");
    }//no drop in else bc return
    assert check(0, -1);
    //valid bc return
    let tmp = a.a;
    //drop at end
}

func main(){
    if_ret(true, 5);
    assert check(1, 5);
    reset();
    
    if_ret(false, 10);
    assert check(1, 10);
}