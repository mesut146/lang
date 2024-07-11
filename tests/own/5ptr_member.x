import own/common
import std/deque

func test(pp: B*, id: i32){
    //p.b.drop()
    pp.b = A{a: id};
    check_ids(10);
}

func test2(){
    let b = B{b: A{a: 10}};
    test(&b, 20);
}

func main(){
    test2();
    check_ids(10, 20);
}