import own/common
import std/deque

func test(c: bool){
    let i = 0;
    let a = A{a: ++i};
    while(i <= 4){
        if(c){
            send(a);
            a = A{a: ++i};
        }
        assert check(i - 1, i - 1);
        if(i == 5) break;
    }
    assert check_ids([1,2,3,4][0..4]);
    reset();
}

func main(){
    test(true);
    assert check(1, 5);
}