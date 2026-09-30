func fib(n: i32): i32{
    if(n < 2){
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

func apply(f: func(i32) => i32, v: i32): i32{
    return f(v);
}

func main(){
    assert(fib(10) == 55);
    let dbl = |x: i32|: i32{
        return x * 2;
    };
    assert(apply(dbl, 21) == 42);
    let total = 0;
    for(let i = 0;i < 10;++i){
        if(i % 2 == 0){
            continue;
        }
        if(i > 7){
            break;
        }
        total += i;
    }
    assert(total == 1 + 3 + 5 + 7);
    print("recursion done\n");
}
