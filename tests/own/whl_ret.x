import own/common

func whl_ret(c: bool, id: i32){
    let a = A{a: id};
    let i = 0;
    while(++i < 5){
        if(c){
            a = A{a: id + 1};//a.drop
            assert check(1, id);
            return;
        }else{
            let tmp = a.a;
        }
        let tmp = a.a;
    }
    //drop at end
}

func main(){
    whl_ret(true, 1);
    reset();
    whl_ret(false, 2);
    assert check(1, 2);
}