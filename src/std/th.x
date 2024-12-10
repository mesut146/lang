import std/any
import std/llist

struct Thread{
    id: i64;
}
struct thread;//just for namespace 

func th_bridge<T>(fp: func(T*)=>void, arg: c_void*){
    fp(arg as T*);
}

impl thread{
  func spawn(fp: func(c_void*) => void): Thread{
    let id: i64 = 0;
    let code = pthread_create(&id, ptr::null<pthread_attr_t>(), fp, ptr::null<c_void>());
    if(code != 0){
      panic("thread spawn failed, code={}", code);
    }
    return Thread{id: id};
  }
  func spawn_arg<T>(fp: func(c_void*) => void, arg: T*): Thread{
    let id: i64 = 0;
    let code = pthread_create(&id, ptr::null<pthread_attr_t>(), fp, arg as c_void*);
    if(code != 0){
      panic("thread spawn failed, code={}", code);
    }
    return Thread{id: id};
  }
  func spawn_arg2<T>(fp: func(T*) => void, arg: T*): Thread{
    let id: i64 = 0;
    let code = pthread_create(&id, ptr::null<pthread_attr_t>(), fp as func(c_void*)=>void, arg as c_void*);
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
  func unwrap(*self): T{
      //self.unlock();
      let code = pthread_mutex_destroy(&self.lock);
      if(code != 0){
          let ptr = strerror(code);
          printf("msg=%s\n", ptr);
          panic("mutex destroy failed, code={}", code);
      }
      return self.val;
  }
  func clone2(self): T{
      let res = self.lock().clone();
      self.unlock();
      return res;
  }
}
impl<T> Drop for Mutex<T>{
  func drop(*self){
    self.unlock();
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
  infos: Mutex<LinkedList<Box<WorkerBridgeInfo>>>;
  todo: Mutex<List<Job>>;
}
struct WorkerBridgeInfo{
  fp: func(c_void*) => void;
  arg: Any;
  th: Option<Thread>;
  worker: Worker*;
}

static xxx = false;
  
func worker_bridge(arg: c_void*){
  let info = arg as WorkerBridgeInfo*;
  let fp = info.fp;
  let arg2 = Any::get<c_void>(&info.arg);
  fp(arg2);
  let worker = info.worker;
  //lock
  let infos = worker.infos.lock();
  let todo = worker.todo.lock(); 
  if(xxx) print("finished\n");
  if(infos.len() == 1){
      infos.clear();
  }else{
      let i = 0;
      let cur: Node<Box<WorkerBridgeInfo>>* = infos.head.get();
      while(true){
          if(cur.val.get().th.get().id != info.th.get().id){
              infos.remove(i);
              if(xxx) print("removed {}\n", infos.len());
              break;
          }
          if(cur.next.is_none()) break;
          cur = cur.next.get().get();
          i+=1;
      }
  }
  if(xxx) print("todo {} wc={}\n", todo.len(), infos.len());
  while(!todo.empty() && infos.len() < worker.thread_cnt){
      let job = todo.remove(todo.len() - 1);
      worker.todo.unlock();
      worker.infos.unlock();
      worker.add_arg(job.fp, job.arg);
      infos = worker.infos.lock();
      todo  = worker.todo.lock();
  }
  worker.todo.unlock();
  worker.infos.unlock();
}
  
impl Worker{
  func new(thread_cnt: i32): Worker{
    return Worker{
                  thread_cnt: thread_cnt,
                  infos: Mutex::new(LinkedList<Box<WorkerBridgeInfo>>::new()),
                  todo: Mutex::new(List<Job>::new())
    };
  }

  func get_working(self): i64{
      let infos = self.infos.lock();
      let res = infos.len();
      self.infos.unlock();
      return res;
  }

  func add(self, fp: func(c_void*) => void){
    self.add_arg(fp, Any::new());
  }

  func add_arg<T>(self, fp: func(c_void*) => void, arg: T){
      self.add_arg(fp, Any::new(arg));
  }
  
  func add_arg(self, fp: func(c_void*) => void, arg: Any){
      let infos = self.infos.lock();
      let wc = infos.len();
      if(xxx) print("add_arg wc: {}\n", wc);
      if(wc >= self.thread_cnt){
          let todo = self.todo.lock();
          todo.add(Job{fp, arg});
          if(xxx) print("added todo {}\n", todo.len());
          self.todo.unlock();
          self.infos.unlock();
          return;
      }
      //let infos = self.infos.lock();
      let info = WorkerBridgeInfo{fp: fp,
                       arg: arg,
                       th: Option<Thread>::new(),
                       worker: self
      };
      let bx: Box<WorkerBridgeInfo>* = infos.add(Box::new(info));
      let info_ptr = bx.get();
      let th = thread::spawn_arg(worker_bridge, info_ptr);
      info_ptr.th = Option::new(th);
      if(xxx) print("added1={}\n", infos.len());
      self.infos.unlock();
      if(xxx) print("added {}\n", self.get_working());
  }

  func join(self){
      let infos = self.infos.lock();
      while(!infos.empty()){
          //infos.last().get().th.get().join();
          self.infos.unlock();
          sleep(1);
          infos = self.infos.lock();
      }
      self.infos.unlock();
      //sleep(5);
  }
}