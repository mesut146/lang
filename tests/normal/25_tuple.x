struct A{
    a: i32;
}
struct B{
    a: i32;
}

func get_t1(): (i32){
    return (10, );
}
func get_t11(): (i32, ){
    return (10, );
}
func get_t2(): (i32, A){
    return (10, A{20});
}

func test_type(){
    let t = get_t1();
    let t2 = get_t11();
    let t3 = get_t2();

    assert(t.0 == 10);
    assert(t2.0 == 10);
    assert(t3.0 == 10);
    assert(t3.1.a == 20);
}

func main(){
    let t = (10, );
    let t2 = (10, 20);
    let t3 = (10, A{20}, );
    let t4 = (10, A{20}, B{30});

    assert(t.0 == 10);
    assert(t2.0 == 10);
    assert(t2.1 == 20);
    assert(t3.0 == 10);
    assert(t3.1.a == 20);
    assert(t4.0 == 10);
    assert(t4.1.a == 20);
    assert(t4.2.a == 30);

    test_type();
}