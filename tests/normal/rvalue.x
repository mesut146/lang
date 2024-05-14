struct A{
    a: i32;
}

impl A{
    func st(self){

    }
}

impl i32{
    func prim(self){

    }
}

func struct_test(){
    A{a: 5}.st();
}

func get_prim(): i32{
    return 10;
}

func main(){
    i32::prim(5);
    i32::prim(get_prim());
    6.prim();
    get_prim().prim();
    struct_test();
    print("rvalue test done\n");
}