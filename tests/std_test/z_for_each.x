import std/it

func test_normal(){
    let list = List<i32>::new();
    list.add(11);
    list.add(22);
    list.add(33);
    for x in &list{
        assert(std::typeof(x).eq("i32*"));
        print("x={}\n", x);
    }
    list.drop();
}
func test_into_iter(){
    let list = List<i32>::new();
    list.add(111);
    list.add(222);
    list.add(333);
    for x in list{
        assert(std::typeof(x).eq("i32"));
        print("x2={}\n", x);
    }
}

func slice_iter(){
    let arr = [1111, 2222, 3333];
    let slice = arr[0..3];
    for x in &slice{
        assert(std::typeof(x).eq("i32*"));
        print("x3={}\n", x);
    }
}

func slice_into_iter(){
    let arr = [11111, 22222, 33333];
    let slice = arr[0..3];
    for x in slice{
        assert(std::typeof(x).eq("i32"));
        print("x4={}\n", x);
    }
}

func map_iter(){
    let map = Map<i32, i32>::new();
    map.add(1, 7);
    map.add(2, 11);
    map.add(3, 13);
    for pair in &map{
        assert(std::typeof(pair).eq("Pair<i32, i32>*"));
        print("map.pair={}\n", pair);
    }
}

func map_into_iter(){
    let map = Map<i32, i32>::new();
    map.add(1, 7);
    map.add(2, 11);
    map.add(3, 13);
    for pair in map{
        assert(std::typeof(pair).eq("Pair<i32, i32>"));
        print("map.pair2={}\n", pair);
    }
}

func main(){
    test_normal();
    test_into_iter();
    slice_iter();
    slice_into_iter();
    map_iter();
    map_into_iter();
    print("for_each done\n");
}