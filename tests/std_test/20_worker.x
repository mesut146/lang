import std/any
import std/th

struct A{
    a: i64;
    b: i64;
    c: i64;
}

func f1(arg: c_void*){
    print("f1\n");
    sleep(2);
    print("f1 end\n");
}

func f2(arg: c_void*){
    let a = arg as A*;
    print("f2 {} {} {}\n", a.a, a.b, a.c);
    //for(let i = 0;i < 10;++i){}
    sleep(1);
    print("f2 end\n");
}

func test_arg(){
    let worker = Worker::new(2);
    worker.add_arg(f2, A{a: 1, b: 2, c: 3});
    worker.add_arg(f2, A{a: 10, b: 20, c: 30});
    worker.add_arg(f2, A{a: 100, b: 200, c: 300});
    worker.add_arg(f2, A{a: 1000, b: 2000, c: 3000});
    worker.join();
}

func test_normal(){
    let worker = Worker::new(1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.join();
    sleep(4);
}

func test_normal2(){
    let worker = Worker::new(2);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.join();
    //sleep(10);
}
func test_normal3(){
    let worker = Worker::new(3);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.add(f1);
    worker.join();
    //sleep(10);
}

func main(){
    //test_normal();
    //test_normal2();
    //test_normal3();
    test_arg();
}