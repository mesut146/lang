class A{
    a: i32;
    b: [i32; 100];
}

func make_arr(): [i32; 100]{
    return [0; 100];
}

func make_A(): A{
    let arr = [0; 100];
    let obj = A{a: 10, b: arr};
    return obj;
}

func retTest(){
    let arr = [0; 100];
    //let obj = A{a: 10, b: arr};
    print("retTest done\n");
}