import own/common
import std/deque

func test(){
    let i = 1;
    let a = A::new(i);
    while(i <= 4){
        //a.drop()
        a = A::new(++i);
        check_ids(i - 1);
        reset();
        if(i == 5) break;
    }
    check_ids();
}

func main(){
    test();
    check_ids(5);
}