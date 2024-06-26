import own/common
import std/deque

func test(p: A*){
    let id = p.a;
    //p.drop()
    *p = A{a: id + 1};
    check_ids(id);
}

func test2(id: i32){
    let a = A{a: id};
    test(&a);
    //a.drop();
}

func main(){
    test2(10);
    check_ids(10, 11);
}