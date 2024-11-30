import std/th

func f(arg: c_void*){
    let m = arg as Mutex<i32>*;
    let ptr = m.lock();
    *ptr = *ptr + 1;
    print("{} ", ptr);
    m.unlock();
}

func main(){
    let m = Mutex::new(0);
    let th_cnt = 32;
    let arr = List<Thread>::new(th_cnt);
    for(let i = 1;i <= th_cnt;++i){
        let th = thread::spawn_arg(f, &m);
        arr.add(th);
        if(i %8 == 0) sleep(1);
    }
    for th in &arr{
        th.join();
    }
    sleep(1);
    let val = m.unwrap();
    print("mutex={}\n", val);
    assert(val == 32);
    arr.drop();
    print("mutex2 done\n");
}