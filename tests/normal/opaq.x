struct A{
    a: i32;
    b: i64;
}

func take(ptr: A*){
    assert ptr.a == 10;
}

func main(){
    print("opaq run\n");

    let obj = A{a: 10, b: 20i64};
    take(&obj);
}