import own/common
import std/deque

func test(){
    let i = 0;
    let a = A{a: ++i};
    while(i <= 4){
        //a.drop()
        a = A{a: ++i};
        assert check(i - 1, i - 1);
        if(i == 5) break;
    }
    assert check_ids([1,2,3,4][0..4]);
    reset();
    //print("after while\n");
    //A::drop 1
    //A::drop 2
    //A::drop 3
    //A::drop 4
    //after while
    //A::drop 5
}

func main(){
    test();
    assert check(1, 5);
}