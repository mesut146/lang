struct A{
    a: i32;
    b: i64;
}

func take(ptr: A*){
    let a = ptr.a;
}

func main(){
    print("opaq run\n");

    let obj = A{a: 10, b: 20i64};
    //obj.a = 11;
    take(&obj);
}