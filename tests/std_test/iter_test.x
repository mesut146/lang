func test_iter(){
    let list = List<i32>::new();
    list.add(11);
    list.add(22);
    let it = list.iter();
    while(true){
        let cur: Option<i32*> = it.next();
        if(cur.is_none()) break;
        print("cur={}\n", cur.unwrap());
    }
    print("list={}\n", &list);
    list.drop();
}

func test_iter_mut(){
    let list = List<i32>::new();
    list.add(33);
    list.add(44);
    let it = list.iter();
    while(true){
        let cur: Option<i32*> = it.next();
        if(cur.is_none()) break;
        let ptr = cur.unwrap();
        //*cur.unwrap() += 1;
        *ptr = *ptr + 1;
    }
    print("list={}\n", &list);
    list.drop();
}

func test_into_iter(){
    let list = List<i32>::new();
    list.add(55);
    list.add(66);
    let it = list.into_iter();
    while(true){
        let cur: Option<i32> = it.next();
        if(cur.is_none()) break;
        print("cur={}\n", cur.unwrap());
    }
    it.drop();
}

func main(){
    test_iter();
    test_iter_mut();
    test_into_iter();
    print("iter_test done\n");
}