import own/common

func if_ret(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        assert check(1, id);
        return;
        //panic("");
    }//no else generated bc return
    print("after if\n");
    //valid bc return
    a.a += 1;
    //a.drop()
}

func main(){
    if_ret(true, 5);
    assert check(1, 5);
    
    if_ret(false, 10);
    assert check(2, 11);
}