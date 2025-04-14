import std/hashmap
import std/map

func map_i32(){
    let map = HashMap<i32, i32>::new();
    let max = 200;
    for(let i = 1;i <= max;++i){
        map.insert(i, i * i);
    }
    assert(map.len() == max);
    
    //iter test
    let cnt = 0;
    for p in &map{
        ++cnt;
    }
    assert(cnt == max);
    
    for(let i = 1;i <= max;++i){
        let opt= map.get(&i);
        assert(opt.is_some());
        //assert2(opt.is_some(), format("no key '{}'", i));
        let val: i32* = opt.unwrap();
        assert_eq(*val, i * i);
    }
}

func keys_test(){
    let map = HashMap<i32, i32>::new();
    let max = 20;
    for(let i = 1;i <= max;++i){
        map.insert(i, i * i);
    }
    let keys = to_list2(map.keys());
    keys.sort();
    print("keys={:?}\n", keys);
}

func hex(x: i32, s: String*){
    if(x < 10){
        s.append(i32::str(x));
    }else{
        s.append(('a' + x - 10) as i8);
    }
}

func map_str(){
    let map = HashMap<String, String>::new();
    for(let r = 0;r < 256;r += 35){
        for(let g = 0;g < 256;g += 35){
            for(let b = 0;b < 256;b += 35){
                let k = String::new();
                let v = String::new();
                hex(r / 16, &k);
                hex(r % 16, &k);
                hex(g / 16, &k);
                hex(g % 16, &k);
                hex(b / 16, &k);
                hex(b % 16, &k);
                if(r >= g){
                    if(r >= b){
                        v.append("red");
                    }else{
                        v.append("blue");
                    }
                }else{
                    if(g >= b){
                        v.append("green");
                    }else{
                        v.append("blue");
                    }
                }
                map.add(k, v);
            }
        }
    }
    assert(map.len() == 512);
   // print("len={}\n\n", map.len());
    for p in &map{
        let c = to_color(p.a.str());
        if(!c.eq(p.b.str())){
            panic("key={} val={} c={}\n", p.a, p.b, c);
        }
    }
}

func to_color(s: str): str{
    let r = i32::parse_hex(s.substr(0, 2)).unwrap();
    let g = i32::parse_hex(s.substr(2, 4)).unwrap();
    let b = i32::parse_hex(s.substr(4, 6)).unwrap();
    if(r >= g){
        if(r >= b){
            return "red";
        }else{
            return "blue";
        }
    }else{
        if(g >= b){
            return "green";
        }else{
            return "blue";
        }
    }
}

func same_hash(){
    let map = HashMap<str, i32>::new();
    map.add("Ea", 5);
    map.add("FB",6);
    print("map={:?}\n", map);
}

func remove_test(){
    let map = HashMap<str, i32>::new();
    map.add("foo", 10);
    map.add("bar", 20);
    map.add("baz", 30);
    assert(map.len() == 3);
    map.remove(&"foo");
    assert(map.len() == 2);
    assert(map.get(&"foo").is_none());
    assert(map.get(&"bar").is_some());
    assert(map.get(&"baz").is_some());
}

func main(){
    map_i32();
    map_str();
    same_hash();
    remove_test();
    print("hashmap test done\n");
}