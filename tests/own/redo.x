import own/common

func test(){
    let a = A{a: 1};
    send(a);
    assert check(1, 1);
    reset();
    a = A{a: 2};//no drop bc moved
    assert check(0, -1);
    a = A{a: 3};//a.drop()
    assert check(1, 2);
    reset();
    a.a += 1;
    //a.drop()
}

func main(){
    test();
    assert check(1, 4);
    // A::drop 1
    // A::drop 2
    // A::drop 4
}