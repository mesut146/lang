import std/any

struct A{
    a: i64;
    b: i64;
    c: i64;
}

func main(){
    let a1 = Any::new(10);
    let val = Any::get<i32>(&a1);
    print("a={}\n", val);

    let a2 = Any::new(A{a: 10, b: 20, c: 30});
    let val2 = Any::get<A>(&a2);
    print("a={}\nb={}\nc={}\n", val2.a, val2.b, val2.c);
}