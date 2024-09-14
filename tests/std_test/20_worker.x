import std/any

struct A{
    a: i64;
    b: i64;
    c: i64;
}

func f1(arg: c_void*){
    print("f1\n");
    sleep(1);
    print("f1 end\n");
}

func f2(arg: c_void*){
    let a = arg as A*;
    print("f2 {} {} {}\n", a.a,a.b,a.c);
    sleep(1);
    print("f2 end\n");
}

func test_arg(){
    let worker = Worker::new(3);
    worker.add2(f2, A{a: 1, b: 2, c: 3});
    worker.add2(f2, A{a: 10, b: 20, c: 30});
    worker.add2(f2, A{a: 100, b: 200, c: 300});
    worker.add2(f2, A{a: 1000, b: 2000, c: 3000});
    worker.join();
}

func test_normal(){
    let worker = Worker::new(3);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.join();
}

func main(){
    test_normal();
    test_arg();
}