func test_normal(){
    let list = List<i32>::new();
    list.add(11);
    list.add(22);
    list.add(33);
    for x in &list{
        print("x={}\n", x);
    }
    list.drop();
}
func test_into_iter(){
    let list = List<i32>::new();
    list.add(111);
    list.add(222);
    list.add(333);
    for y in list{
        print("y={}\n", y);
    }
}

func main(){
    test_normal();
    test_into_iter();
    print("for_each done\n");
}