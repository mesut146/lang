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
        check_ids(i - 1);
        reset();
        if(i == 5) break;
    }
    check_ids();
}

func main(){
    test(true);
    check_ids(5);
}