import own/common
import std/deque

func if_transfer(c: bool){
    let a = A{a: 10};
    if(c){
        send(a);
    }
    //send(a);
}

func if_inner(c: bool){
    let a = A{a: 10};
    if(c){
        let b = a;
    }
    //send(a);
}