import std/th

static cnt: Mutex<i32> = Mutex<i32>::new(0);

func f11(arg: c_void*){
    let ptr = cnt.lock();
    *ptr = *ptr + 1;
    print("f11: {}\n", ptr);
    //print("f11: {}\n", *ptr); fails
    cnt.unlock();
    sleep(3);
}

func main(){
    let th_cnt = 4;
    let arr = List<Thread>::new(th_cnt);
    for(let i = 0;i < th_cnt;++i){
        let th = thread::spawn(f11);
        arr.add(th);
    }
    for th in &arr{
        th.join();
    }
    arr.drop();
}