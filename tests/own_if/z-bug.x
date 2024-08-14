import own/common

func test(id: i32, c1: bool, c2: bool){
    let a = A::new(id);
    if(c1){
        send(a);
    }else{
        if(c2){
            send(a);
        }else{
            send(a);
            return;//any jump will do same
        }
    }
}

func main(){
    test(100, true, false);
    pop_ids(100);

    test(101, false, true);
    pop_ids(101);
    
    test(102, false, false);
    pop_ids(102);
    print("bug done\n");
}