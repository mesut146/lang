import std/th

static lock = make_pthread_mutex_t();
static cnt: i32 = 0;

func f1(arg: c_void*){
    pthread_mutex_lock(&lock);
    cnt += 1;
    print("f1: {}\n", cnt);
    sleep(1);
    pthread_mutex_unlock(&lock);
}

func main(){
    pthread_mutex_init(&lock, ptr::null<pthread_mutexattr_t>());
    let th_cnt = 5;
    let arr = List<Thread>::new(th_cnt);
    for(let i = 0;i < th_cnt;++i){
        let th = thread::spawn(f1);
        arr.add(th);
    }
    for th in &arr{
        th.join();
    }
    pthread_mutex_destroy(&lock); 
    arr.drop();
}