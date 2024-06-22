func test_format(){
    let h = "hello";
    let s = format("{} world\n", h);
    s.print();
    //Drop::drop(s);
    //s.drop();
}

func test_print(){
    print("test_print\n");
}

func test_print2(){
    let h = "hi";
    let t = "there";
    print("{} {}\n", h, t);
}

func test_panic(){
    panic("test_panic\n");
}

func test_panic2(){
    let err = "err msg";
    panic("test_panic2 '{}'\n", err);
}

func main(){
    test_format();
    test_print();
    test_print2();
    //test_panic();
    //test_panic2();
}
