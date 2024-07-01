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
    reset();
    if(c){
        a = A::new(id + 1);
    }else{
        a = A::new(id + 2);
    }
    send(a);
}

func main(){
    test();
    check_ids(4);
    // A::drop 1
    // A::drop 2
    // A::drop 4

    redo_both(10, true);
    check_ids(10, 11);
    reset();

    redo_both(20, false);
    check_ids(20, 22);
    reset();
}