import own/common

func test(){
    let a = A{a: 1};
    send(a);
    check_ids(1);
    reset();
    a = A{a: 2};//no drop bc moved
    check_ids();
    a = A{a: 3};//a.drop()
    check_ids(2);
    reset();
    a.a += 1;
    //a.drop()
}

func redo_both(id: i32, c: bool){
    let a = A::new(id);
    send(a);
    if(c){
        a = A::new(id + 1);
    }else{
        a = A::new(id + 2);
    }//no drop
    let aa = a.a;
    while(false){
        let bb = a.a;
    }
}

func redo_else(id: i32, c: bool){
    let aa = A::new(id);
    send(aa);
    if(c){
    }else{
        aa = A::new(id + 1);
        //aa.drop();
    }
    //invalid
    //send(aa);
    //panic("impossible");
}

func redo_if(id: i32, c: bool){
    let aa = A::new(id);
    send(aa);
    if(c){
        aa = A::new(id + 1);
        //aa.drop();
    }
    //invalid
    //send(aa);
    //panic("impossible");
}

func main(){
    test();
    check_ids(4);
    reset();

    redo_both(10, true);
    check_ids(10, 11);
    reset();

    redo_both(20, false);
    check_ids(20, 22);
    reset();

    redo_else(50, true);
    check_ids(50);
    reset();

    redo_else(60, false);
    check_ids(60, 61);
    reset();

    redo_if(30, true);
    check_ids(30, 31);
    reset();

    redo_if(40, true);
}