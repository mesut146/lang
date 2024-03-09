import own/common
import std/deque

func arg(){
    let b = B::new(1000);
    //send(b.b);
}

func var_decl(){
    let b = B::new(1000);
    //let tmp = b.b;
}

func main(){
    let a = A{a: 100};
    let b = B::new(1000);
    //a = b.b;
}