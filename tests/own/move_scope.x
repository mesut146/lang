import own/common

func test(c: bool, id: i32){
    let a = A{a: id};
    if(c){
        let b = a;
        ++b.a;
        //b.drop
    }//a.drop in else
}

func if_if(c1: bool, c2: bool){
    let a = A{a: 5};
    let b = A{a: 17};
    if(c1){
        if(c2){
            let c = a;
            c.a = 7;
            //endscope c.drop() -> a.drop()
            //endbranch b.drop() bs else moves
        }
        else{
            let d = b;
            d.a = 19;
            //endscope d.drop() -> b.drop()
            //endbranch a.drop bc then moves
        }
        //cleanup shouldn't drop b, already dropped in else
        //a -> moved, b -> moved
    }else{
        if(c2){
            let e = b;
            e.a = 23;
            //e.drop() -> b.drop()
        }else{
            //a.drop()
            a = b;
            assert check(0, -1);
            reset();
            //!b.drop bc then moves=no drop
        }
        //b->moved, a->valid but a moved in :17 so mark as moved too
    }
    //if_next_15
}//no drop

func test_if_if(){
    if_if(true, true);
}

func main(){
    /*test(true, 1);
    assert check(1, 2);
    reset();
    test(false, 3);
    assert check(1, 3);
    reset();*/

    test_if_if();
}