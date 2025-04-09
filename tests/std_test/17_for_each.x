import std/it

func test_normal(){
    let list = List<i32>::new();
    list.add(11);
    list.add(22);
    list.add(33);
    let arr = [11, 22, 33];
    let i = 0;
    for x in &list{
        assert(std::typeof(x).eq("i32*"));
        assert(*x == arr[i]);
        i += 1;
    }
    list.drop();
}
func test_into_iter(){
    let list = List<i32>::new();
    list.add(111);
    list.add(222);
    list.add(333);
    let arr = [111, 222, 333];
    let i = 0;
    for x in list{
        assert(std::typeof(x).eq("i32"));
        assert(x == arr[i]);
        i += 1;
    }
}

func slice_iter(){
    let arr = [1111, 2222, 3333];
    let slice = arr[0..3];
    let i = 0;
    for x in &slice{
        assert(std::typeof(x).eq("i32*"));
        assert(*x == arr[i]);
        i += 1;
    }
}

func slice_into_iter(){
    let arr = [11111, 22222, 33333];
    let slice = arr[0..3];
    let i = 0;
    for x in slice{
        assert(std::typeof(x).eq("i32"));
        assert(x == arr[i]);
        i += 1;
    }
}

func map_iter(){
    let map = Map<i32, i32>::new();
    map.add(1, 7);
    map.add(2, 11);
    map.add(3, 13);
    let keys = [1, 2, 3];
    let vals = [7, 11, 13];
    let i = 0;
    for pair in &map{
        assert(std::typeof(pair).eq("Pair<i32*, i32*>"));
        assert_eq(*pair.a, keys[i]);
        assert_eq(*pair.b, vals[i]);
        i += 1;
    }
}

func map_into_iter(){
    let map = Map<i32, i32>::new();
    map.add(1, 7);
    map.add(2, 11);
    map.add(3, 13);
    let keys = [1, 2, 3];
    let vals = [7, 11, 13];
    let i = 0;
    for pair in map{
        assert(std::typeof(pair).eq("Pair<i32, i32>"));
        assert(pair.a == keys[i]);
        assert(pair.b == vals[i]);
        i += 1;
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