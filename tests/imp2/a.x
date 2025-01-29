import imp2/b

struct A{
    a: i32;
}

func get(): B{
    return B{b: 111};
}

func getA(): A{
    return A{a: 222};
}