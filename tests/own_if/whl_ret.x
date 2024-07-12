import own/common

func whl_ret(c: bool, id: i32){
    let a = A{a: id};
    let i = 0;
    while(++i < 5){
        if(c){
            Drop::drop(a);
            a = A{a: id + 1};//a.drop
            check_ids(id);
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
    while(i <= 2){
        let a = A::new(id);
        ++i;
        ++id;
        if(c){
            //a.drop()
            continue;
        }
        //valid
        a.check();
    }
}

func while_continue2(){
    let id = 200;
    let c = true;
    let i = 0;
    while(i <= 2){
        let a = A::new(id);
        ++i;
        ++id;
        if(c){
            send(a);
            continue;
        }
        //valid
        a.check();
    }
}

func main(){
    whl_ret(true, 10);
    check_ids(10, 11);
    reset();
    
    whl_ret(false, 20);
    check_ids(20);
    reset();

    while_continue();
    reset();

    while_continue2();
    check_ids(200, 201, 202);
}