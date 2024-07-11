import own/common
import std/deque

func deref_mut(p: A*){
    let id = p.a;
    //p.drop()
    *p = A{a: id + 1};
    check_ids(id);
}

func test(id: i32){
    let a = A{a: id};
    deref_mut(&a);
    //a.drop();
}

func main(){
    test(10);
    check_ids(10, 11);
}