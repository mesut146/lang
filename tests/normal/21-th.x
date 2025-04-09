func f(arg: c_void*){
    printf("th started\n");
    sleep(1);
    printf("after sleep\n");
}

func f2(arg: c_void*){
    printf("th2 started arg=%d\n", *(arg as i32*));
}

struct A{
    a: i64;
    b: i64;
    c: i64;
}

func f3(arg: c_void*){
    let a = arg as A*;
    printf("th2 started arg=%d %d %d\n", a.a, a.b, a.c);
}

func main(){
    let id: i64 = 0;
    printf("Before Thread\n");
    pthread_create(&id, ptr::null<pthread_attr_t>(), f, ptr::null<c_void>());
    pthread_join(id, ptr::null<c_void*>());
    printf("After Thread\n");

    //args
    let x = 1234;
    pthread_create(&id, ptr::null<pthread_attr_t>(), f2, &x as c_void*);
    pthread_join(id, ptr::null<c_void*>());

    let a = A{100, 200, 300};
    pthread_create(&id, ptr::null<pthread_attr_t>(), f3, &a as c_void*);
    pthread_join(id, ptr::null<c_void*>());
}