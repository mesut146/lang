import own/common

func if_else_2_var(c: bool, id: i32, id2: i32){
    let a = A{a: id};
    let b = A{a: id2};
    if(c){
        send(a);
        check_ids(id);
        //b.drop();
    }else{
        send(b);
        check_ids(id2);
        //a.drop();
    }
}
func main(){
    if_else_2_var(true, 10, 15);
    check_ids(10, 15);
    reset();

    if_else_2_var(false, 20, 25);
    check_ids(25, 20);
    reset();
}