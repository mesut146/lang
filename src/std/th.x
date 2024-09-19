import std/any

struct Thread{
    id: i64;
}
struct thread;
  
impl thread{
  func spawn(fp: func(c_void*) => void): Thread{
    let id: i64 = 0;
    let code = pthread_create(&id, ptr::null<pthread_attr_t>(), fp, ptr::null<c_void>());
    if(code != 0){
      panic("thread spawn failed, code={}", code);
    }
    return Thread{id: id};
  }
  func spawn2<T>(fp: func(c_void*) => void, arg: T*): Thread{
    let id: i64 = 0;
    let code = pthread_create(&id, ptr::null<pthread_attr_t>(), fp, arg as c_void*);
    if(code != 0){
      panic("thread spawn failed, code={}", code);
    }
    return Thread{id: id};
  }
}
  
impl Thread{
  func join(self){
    let code = pthread_join(self.id, ptr::null<c_void*>());
    if(code != 0){
      let ptr = strerror(code);
      printf("thread join failed, code=%d %s\n", code, ptr);
      exit(1);
    }
  }
}

struct Mutex<T>{
  lock: pthread_mutex_t;
  val: T;
}
impl<T> Mutex<T>{
  func new(val: T): Mutex<T>{
    let lock = make_pthread_mutex_t();
    let code = pthread_mutex_init(&lock, ptr::null<pthread_mutexattr_t>());
    if(code != 0){
      panic("mutex init failed, code={}", code);
    }
    return Mutex{lock: lock, val: val};
  }
  func lock(self): T*{
    let code = pthread_mutex_lock(&self.lock);
    if(code != 0){
      panic("mutex lock failed, code={}", code);
    }
    return &self.val;
  }
  func unlock(self){
    let code = pthread_mutex_unlock(&self.lock);
    if(code != 0){
      panic("mutex unlock failed, code={}", code);
    }
  }
}
impl<T> Drop for Mutex<T>{
  func drop(*self){
    let code = pthread_mutex_destroy(&self.lock);
    if(code != 0){
      panic("mutex destroy failed, code={}", code);
    }
  }
}


struct ThreadInfo{
  th: Thread;
  is_running: bool;
}
struct Job{
  fp: func(c_void*) => void;
  arg: Any;
}

struct Worker{
  thread_cnt: i32;
  infos: List<Box<WorkerBridgeInfo>>;
  list: List<ThreadInfo>;
  todo: List<Job>;
  lock: pthread_mutex_t;
  done: List<i32>;
}
  
struct WorkerBridgeInfo{
  fp: func(c_void*) => void;
  arg: Any;
  worker: Worker*;
  idx: i32;
}
  
func worker_bridge(arg: c_void*){
  let info = arg as WorkerBridgeInfo*;
  let fp = info.fp;
  let arg2 = Any::get<c_void>(&info.arg);
  fp(arg2);
  let worker = info.worker;
  pthread_mutex_lock(&worker.lock);
  worker.done.add(info.idx);
  let th_info = worker.list.get_ptr(info.idx);
  th_info.is_running = false;
  //worker.infos.remove(info.idx);
  //worker.list.remove(info.idx);
  while(!info.worker.todo.empty() && worker.get_working() < worker.thread_cnt){
    let job = info.worker.todo.remove(worker.todo.len() - 1);
    let info2 = WorkerBridgeInfo{fp: job.fp, arg: job.arg, worker: worker, idx: worker.list.len() as i32};
    let info2_ptr = worker.infos.add(Box::new(info2));
    worker.list.add(ThreadInfo{thread::spawn2(worker_bridge, info2_ptr.get()), true});
  }
  pthread_mutex_unlock(&worker.lock);
}
  
impl Worker{
  func new(thread_cnt: i32): Worker{
    let lock = make_pthread_mutex_t();
    pthread_mutex_init(&lock, ptr::null<pthread_mutexattr_t>());
    return Worker{thread_cnt: thread_cnt,
                  infos: List<Box<WorkerBridgeInfo>>::new(),
                  list: List<ThreadInfo>::new(),
                  todo: List<Job>::new(),
                  lock: lock,
                  done: List<i32>::new()
                };
  }

  func get_working(self): i64{
    let cnt = 0;
    for(let i = 0;i < self.list.len();++i){
      if(self.list.get_ptr(i).is_running){
        cnt += 1;
      }
    }
    return cnt;
  }

  func add(self, fp: func(c_void*) => void){
    if(self.get_working() < self.thread_cnt){
      let info = WorkerBridgeInfo{fp: fp, arg: Any::new(), worker: self, idx: self.list.len() as i32};
      let info_ptr = self.infos.add(Box::new(info));
      self.list.add(ThreadInfo{thread::spawn2(worker_bridge, info_ptr.get()), true});
      return;
    }
    self.todo.add(Job{fp, Any::new()});
  }

  func add_arg<T>(self, fp: func(c_void*) => void, arg: T){
    let a = Any::new(arg);
    // let aptr = a.get<T>();
    //let aptr = Any::get<T>(&a);

    if(self.get_working() < self.thread_cnt){
      let info = WorkerBridgeInfo{fp: fp, arg: a, worker: self, idx: self.list.len() as i32};
      let info_ptr = self.infos.add(Box::new(info));
      self.list.add(ThreadInfo{thread::spawn2(worker_bridge, info_ptr.get()), true});
      return;
    }
    self.todo.add(Job{fp, a});
  }

  func join(self){
    /*while(!self.list.empty()){
      self.list.last().th.join();
    }*/
    /*for pair in &self.list{
      pair.join();
    }*/
    while(self.get_working() > 0 || !self.todo.empty()){
      sleep(1);
    }
  }
}