import own/common

func test(a: A, b: A){
    let a_id = a.a;
    send(a);
    assert check(1, a_id);
    //b.drop()
}

func main(){
    let a = A{a: 1};
    let b = A{a: 2};
    test(a, b);
    assert check(2, 2);
    //A::drop 1
    //A::drop 2
}