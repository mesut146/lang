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
    check_ids(100);reset();

    test(101, false, true);
    check_ids(101);reset();
    
    test(102, false, false);
    check_ids(102);reset();
    print("bug done\n");
}