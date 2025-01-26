import std/hashmap

func map_i32(){
    let map = HashMap<i32, i32>::new();
    for(let i = 1;i < 20;++i){
        map.insert(i, i * i);
    }
    for(let i = 1;i < 20;++i){
        let val: i32* = map.get(&i).unwrap();
        assert_eq(*val, i * i);
    }
}

func map_str(){
    let map = HashMap<str, str>::new();
    map.insert("a", "hello");
    map.insert("b", "world");
    map.insert("c", "...");
    print("map={:?}\n", map);
}

func main(){
    map_i32();
    map_str();
    print("hashmap test done\n");
}