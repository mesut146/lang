import own/common

func test(){
    let a = A{a: 1};
    let b = a;//no drop
    b.a = 2;
    assert check(0, -1);
    //b.drop()
}

func main(){
    test();
    assert check(1, 2);
}
