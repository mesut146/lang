import std/th

func f(arg: c_void*){
    let m = arg as Mutex<i32>*;
    let ptr = m.lock();
    *ptr = *ptr + 1;
    print("{} ", ptr);
    m.unlock();
}

func main(){
    let m = Mutex::new<i32>(0);
    let th_cnt = 5;
    let arr = List<Thread>::new(th_cnt);
    for(let i = 1;i <= th_cnt;++i){
        let th = thread::spawn_arg(f, &m);
        arr.add(th);
    }
    for th in &arr{
        th.join();
    }
    sleep(1);
    let val = m.unwrap();
    print("mutex={}\n", val);
    assert(val == th_cnt);
    arr.drop();
    print("mutex2 done\n");
}