import incremental_test/b

struct A{
    a: i32;
    b: i32;
}

func getB(): B{
    return B{b: 111};
}

func getA(): A{
    return A{a: 222, b: 4444};
}

struct C{
    a: i32;
    //b: i32;
}