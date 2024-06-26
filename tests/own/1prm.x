import own/common

func test(a: A, b: A){
    let a_id = a.a;
    send(a);
    check_ids(a_id);
    //b.drop()
}

func main(){
    let a = A{a: 1};
    let b = A{a: 2};
    test(a, b);
    check_ids(1, 2);
    //A::drop 1
    //A::drop 2
}