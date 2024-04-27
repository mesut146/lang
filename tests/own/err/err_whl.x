import own/common
import std/deque

func test(c: bool, c2: bool){
    let a = A::new(10);
    while(c){
        if(c2){
            send(a); //this also invalid, second iter fails
        }
        else{
          //valid at first but not next iters
        }
        //invalid
    }
    //invalid
}

//else reachable from if, bc they are in loop


func test2(){
    let a = A::new(10);
    while(true){
        send(a);//fails
    }
    //invalid
}