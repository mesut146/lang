import own/common
import std/deque

func test(){
    let a = A{a: 1};
    assert check(0, -1);
    //a.drop();
    a = A{a: 2};
    assert check(1, 1);
    //a.drop();
    a = A{a: 3};
    assert check(2, 2);
    //A::drop 1
    //A::drop 2
    //A::drop 3
}

func main(){
    test();
    assert check(3, 3);
}
