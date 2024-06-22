import own/common

func whl_ret(c: bool, id: i32){
    let a = A{a: id};
    let i = 0;
    while(++i < 5){
        if(c){
            Drop::drop(a);
            a = A{a: id + 1};//a.drop
            assert check(1, id);
            return;
        }else{
            let tmp = a.a;
        }
        let tmp = a.a;
    }
    //drop at end
    Drop::drop(a);
}


func while_continue(){
    let id = 100;
    let c = true;
    let i = 0;
    while(++i < 5){
        let a = A::new(id);
        if(c){
            send(a);
            continue;
        }
        //valid
        a.check(id);
    }
}

func main(){
    whl_ret(true, 10);
    assert check_ids([10, 11][0..2]);
    reset();
    whl_ret(false, 20);
    assert check(1, 20);

    while_continue();
}