struct A{
    a: i32;
}

impl A{
    func new(a: i32): A{
        return A{a: a};
    }
    func st(self){

    }
}

impl i32{
    func prim(self){

    }
}

func struct_test(){
    A{a: 5}.st();

    let a = &A::new(10);
    assert(a.a == 10);
}

func get_prim(): i32{
    return 10;
}

func rvalue_test(){
    let ptr = &5;
    assert(*ptr == 5);

    let ptr2 = &get_prim();
    assert(*ptr2 == 10);
}

func main(){
    i32::prim(5);
    i32::prim(get_prim());
    6.prim();
    get_prim().prim();
    struct_test();
    rvalue_test();
    print("rvalue test done\n");
}