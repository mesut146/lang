func deref_prim(){
    let a: i32 = 100;
    let p = &a;
    let a2 = ptr::deref(p);
    assert a2 == 100;
}

struct A{
    a: i32;
    b: i64;
}
func deref_struct(){
    let a = A{a: 200, b: 300};
    let p = &a;
    let a2 : A = ptr::deref(p);
    assert a2.a == 200;
    assert a2.b == 300;
}

func main(){
    deref_prim();
    deref_struct();
    print("ptr_test done\n");
}