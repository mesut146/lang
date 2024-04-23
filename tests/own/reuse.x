import own/common

func test(){
    let a = A::new(10);
    a = A::new(a.a);
    assert check_ids(10);
}

func main(){
    test();
    assert cnt == 1;
}