import own/common
import std/deque

func test(p: A*){
    //p.drop()
    let id = p.a;
    *p = A{a: id + 1};
    assert check(1, id);
}

func test2(id: i32){
    let a = A{a: id};
    test(&a);
}

func main(){
    test2(10);
    assert check_ids([10,11][0..2]);
}