import own/common
import std/deque

func test(){
    let a = A{a: 11};
    //a.drop();
    a = A{a: 22};
    check_ids(11);
    //a.drop();
    a = A{a: 33};
    check_ids(11, 22);
    //A::drop 11
    //A::drop 22
    //A::drop 33
}

func main(){
    test();
    check_ids(11, 22, 33);
}
