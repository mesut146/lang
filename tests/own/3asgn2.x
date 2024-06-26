import own/common

func test(){
    let a = A{a: 10};
    let b = a;//no drop
    b.a = 20;
    check_ids();
    //b.drop()
}

func main(){
    test();
    check_ids(20);
}
