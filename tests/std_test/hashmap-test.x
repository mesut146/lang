import std/hashmap

func map_i32(){
    let map = HashMap<i32, i32>::new();
    map.insert(1, 7);
    map.insert(2, 11);
    map.insert(3, 13);
    let key = 1;
    let op = map.get(&key);
    //Option<i32*>::debug fails
    print("{} {}\n", std::typeof(op), op.unwrap());
    print("map={}\n", map);
}

func map_str(){
    let map = HashMap<str, str>::new();
    map.insert("a", "hello");
    map.insert("b", "world");
    map.insert("c", "...");
    print("map={}\n", map);
}

func main(){
    map_i32();
    map_str();
    print("hashmap test done\n");
}