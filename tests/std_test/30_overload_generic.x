import std/list

func main(){
    //overloaded generics sharing name+scope+inferred types must not
    //alias: List::new() vs List::new(cap) (regression: instantiation
    //cache keyed without method shape reused the wrong overload)
    let a = List<u8>::new();
    let b = List<u8>::new(10);
    b.add(7 as u8);
    assert(a.len() == 0);
    assert(b.len() == 1);
    assert(*b.get(0) == 7);
    let c = List<i32>::new();
    let d = List<i32>::new(4);
    d.add(42);
    assert(c.len() == 0);
    assert(*d.get(0) == 42);
    print("overload done\n");
}
