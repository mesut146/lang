import own/common

func test(){
    let a = A::new(10);
    //use lhs in rhs
    a = A::new(a.a * 2);
    check_ids(10);
}

func main(){
    test();
    check_ids(10, 20);
}