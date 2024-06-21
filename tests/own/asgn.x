import own/common
import std/deque

func test(){
    let a = A{a: 1};
    //a.drop();
    a = A{a: 2};
    check_ids(1);
    //a.drop();
    a = A{a: 3};
    check_ids(1, 2);
    //A::drop 1
    //A::drop 2
    //A::drop 3
}

func main(){
    test();
    check_ids(1, 2, 3);
}
