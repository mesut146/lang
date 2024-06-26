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

func main(){
    test();
    check_ids(4);
    // A::drop 1
    // A::drop 2
    // A::drop 4
}