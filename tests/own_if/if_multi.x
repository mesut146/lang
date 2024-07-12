import own/common

func main(){
    if_multi(true, false, 50);
    check_ids(50);
    reset();

    while_if_multi(true ,false, 100);
}

func if_multi(c1: bool, c2: bool, id: i32){
    let a = A::new(id);
    if(c1){
        send(a);
    }else{
        if(c2){
            send(a);
        }else{
            a.check(id);
        }
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
            a.check(id);
        }
        check_ids(id);
        ++i;
    }
    check_ids(id);
}