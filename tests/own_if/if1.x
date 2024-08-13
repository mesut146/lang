import own/common

func if_only(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        send(a);
        check_ids(id);
    }else{
        check_ids();
        //a.drop()
    }
    check_ids(id);
    //no drop
}

func level2(id: i32, c1: bool, c2: bool){
    let a = A{a: id};
    if(c1){
        if(c2){
            send(a);
        }else{
            send(a);
        }
    }else{
        send(a);
    }
}

func level3(id: i32, c1: bool, c2: bool, c3: bool){
    let a = A{a: id};
    if(c1){
        if(c2){
            if(c3){
                send(a);
            }else{
                //a.drop()
            }
        }else{
            //a.drop()
        }
    }else{
        //a.drop()
    }
}


func main(){
    if_only(true, 1);
    pop_ids(1);
    
    if_only(false, 2);
    pop_ids(2);

    level2(50, true, true);
    pop_ids(50);

    level2(51, true, false);
    pop_ids(51);

    level2(52, false, true);
    pop_ids(52);
    
    level3(60, true, true, true);
    //panic("");
}