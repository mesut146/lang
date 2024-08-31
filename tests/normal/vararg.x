extern{
    func test(...);

    func test2(a: i32, ...);
}

func main_2(){
    test();
    test(1);
    test(1, 2, "asd");
    test2(3, "aa", 5);
}