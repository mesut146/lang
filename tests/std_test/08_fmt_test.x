func test_format(){
    let h = "hello";
    let s = format!("{} world", h);
    assert(s.eq("hello world"));
    s.drop();
}

func format_named(){
    let s = "hello";
    let x = 42;
    let s2 = format!("{s} {x}");
    assert(s2.eq("hello 42"));
    s2.drop();
}

func test_print(){
    print!("test_print\n");
}

func test_print2(){
    let h = "hi";
    let t = "there";
    print!("{} {}\n", h, t);
}

func test_panic(){
    panic!("test_panic\n");
}

func test_panic2(){
    let err = "err msg";
    panic!("test_panic2 '{}'\n", err);
}

func main(){
    test_format();
    format_named();
    test_print();
    test_print2();
    //test_panic();
    //test_panic2();
}
