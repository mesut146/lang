import own/common
import std/deque

func test(pp: B*, id: i32){
    //p.b.drop()
    pp.b = A{a: id};
    check_ids(10);
}

func test2(){
    let b = B::new(10);
    test(&b, 20);
}

func move_field(){
    let b = B::new(100);
    let ptr = &b;
    send(ptr.b);
    //commenting line below causes error
    ptr.b = A::new(101);
}

func main(){
    //test2();
    //check_ids(10, 20);

    move_field();
}