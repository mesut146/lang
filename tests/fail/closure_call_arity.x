//Calling a lambda value checks the argument count like the function-pointer
//path does. It used to index the declared parameter list out of its end and
//die with a bare `List` panic ("index 0 out of bounds (0, 0)").
// should-fail: arg count do not match
func apply<T>(fp: T, v: i32): i32{
    return fp(v);
}

func main(){
    let zero = ||: i32{ return 7; };
    assert(apply(zero, 1) == 7);
}
