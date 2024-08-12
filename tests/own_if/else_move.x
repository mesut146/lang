import own/common

func else_only(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        check_ids();
        //a.drop()
    }else{
        send(a);
        check_ids(id);
    }
    check_ids(id);
}

func level2(id: i32, c1: bool, c2: bool){
    let a = A{a: id};
    if(c1){
        //a.drop()
    }else{
        if(c2){
            //a.drop()
        }
        else{
            send(a)
        }
    }
}

func level3(id: i32, c1: bool, c2: bool, c3: bool){
    let a = A{a: id};
    if(c1){
        //a.drop()
    }else{
        if(c2){
            //a.drop()
        }
        else{
            if(c3){
                //a.drop()
            }
            else{
                send(a)
            }
        }
    }
}

func main(){
    else_only(true, 3);
    check_ids(3);
    reset();
    else_only(false, 4);
    check_ids(4);
    reset();
}