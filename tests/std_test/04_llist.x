import std/llist

func main(){
    let l = LinkedList<i32>::new();
    let p1 = l.add(10);
    assert(*p1 == 10);
    let p2 = l.add(20);
    assert(*p2 == 20);
    l.add(5);
    assert(*l.get(0) == 10);
    assert(*l.get(1) == 20);
    assert(*l.get(2) == 5);
    print("l={}\n", l);
    assert(l.indexOf(&20) == 1);
    assert(l.indexOf(&5) == 2);
    assert(l.indexOf(&200) == -1);
    l.remove(0);
    assert(*l.get(0) == 20);
    assert(*l.get(1) == 5);
    print("l={}\n", l);
    l.add(30);
    assert(*l.get(2) == 30);
    print("l={}\n", l);
    l.remove(1);
    assert(*l.get(0) == 20);
    assert(*l.get(1) == 30);
    print("l={}\n", l);
    l.drop();
}