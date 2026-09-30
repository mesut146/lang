import std/list

func main(){
    //reserve grows once for bulk appends (regression: growing only
    //one slot per expand() call hung bulk appends forever)
    let l = List<i32>::new();
    l.reserve(100);
    for(let i = 0;i < 100;++i){
        l.add(i);
    }
    assert(l.len() == 100);
    assert(*l.get(99) == 99);
    let s = String::new("");
    s.append("0123456789ABCDEF0123456789ABCDEF");
    s.append("0123456789ABCDEF0123456789ABCDEF");
    assert(s.len() == 64);
    assert(s.eq("0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"));
    print("reserve done\n");
}
