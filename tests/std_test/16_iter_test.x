func test_iter(){
    let list = List<i32>::new();
    list.add(11);
    list.add(22);
    let it = list.iter();
    let arr = [11, 22];
    let i = 0;
    while(true){
        let cur: Option<i32*> = it.next();
        if(cur.is_none()) break;
        assert_eq(*cur.unwrap(), arr[i]);
        i += 1;
    }
    assert_eq(list.len() as i32, 2);
    assert_eq(i, 2);
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
    let arr = [34, 45];
    for(let i = 0;i < list.len();++i){
        assert_eq(*list.get(i), arr[i]);
    }
    list.drop();
}

func test_into_iter(){
    let list = List<i32>::new();
    list.add(55);
    list.add(66);
    let arr = [55, 66];
    let i = 0;
    let it = list.into_iter();
    while(true){
        let cur: Option<i32> = it.next();
        if(cur.is_none()) break;
        assert_eq(cur.unwrap(), arr[i]);
        i += 1;
    }
    assert_eq(i, 2);
    it.drop();
}

func main(){
    test_iter();
    test_iter_mut();
    test_into_iter();
    print("iter_test done\n");
}