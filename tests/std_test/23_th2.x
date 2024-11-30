import std/th

struct A{
    a: i32;
    b: str;
}

func f(arg: A*){
    print("f() {} {}\n", arg.a, arg.b);
    assert(arg.a == 102030);
}

func main(){
    let a = A{a: 102030, b: "hello"};
    let th = thread::spawn_arg2(f, &a);
    th.join();
    print("th2 done\n");
}