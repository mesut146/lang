import std/it

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

func slice_iter(){
    let arr = [1111, 2222, 3333];
    let slice = arr[0..3];
    for z in &slice{
        print("z={}\n", z);
    }
}

func main(){
    test_normal();
    test_into_iter();
    slice_iter();
    print("for_each done\n");
}