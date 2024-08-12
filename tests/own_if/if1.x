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


func main(){
    if_only(true, 1);
    check_ids(1);
    reset();
    if_only(false, 2);
    check_ids(2);
    reset();
}