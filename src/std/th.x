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
    //NB: no unlock here: destroying a held mutex must fail loudly
    //(EBUSY), and unlocking an unlocked one corrupts the counter, so a
    //prior version of this drop failed on EVERY mutex. Holders must
    //unlock before the mutex dies; join() guarantees that for Worker.
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
  //join handles retained here (NOT in the self-removing infos nodes):
  //join() joins every thread before returning, so no thread can still
  //hold a mutex when the Worker drops. Only the owning thread touches
  //this list (workers touch infos/todo), so no mutex needed for it.
  threads: List<Thread>;
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
  //remove SELF, never a peer: peers may still run their jobs, and with
  //auto-drops a removed node is freed immediately, so freeing another
  //thread's node use-after-frees it (garbage sleeps, EBUSY at teardown).
  //the old code removed the first non-self node, which only worked while
  //drops were off and remove() leaked. after this point `info` and `cur`
  //dangle: only `worker` (copied above) and fresh locks are used below.
  let i = 0;
  let cur: Node<Box<WorkerBridgeInfo>>* = infos.head.get();
  while(true){
      if(cur.val.get().th.get().id == info.th.get().id){
          infos.remove(i);
          if(xxx) print("removed {}\n", infos.len());
          break;
      }
      if(cur.next.is_none()) break;
      cur = cur.next.get().get();
      i+=1;
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
                  todo: Mutex::new(List<Job>::new()),
                  threads: List<Thread>::new()
    };
  }

  func get_working(self): i64{
      let infos = self.infos.lock();
      let res = infos.len();
      self.infos.unlock();
      return res;
  }
  func get_todo(self): i64{
      let todo = self.todo.lock();
      let res = todo.len();
      self.todo.unlock();
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
      let tid = th.id;
      info_ptr.th = Option::new(th);
      //retain the handle outside the self-removing node (see threads).
      //id is copied before the move; Thread itself is just the id.
      self.threads.add(Thread{id: tid});
      if(xxx) print("added1={}\n", infos.len());
      self.infos.unlock();
      if(xxx) print("added {}\n", self.get_working());
  }

  func join(self){
      //drain + join until quiescent: a finishing thread can pull from
      //todo and spawn while we join (its node appears after we looked),
      //so a single pass can miss stragglers. Spawns are finite (each
      //consumes a todo entry), so this terminates.
      while(true){
          let infos = self.infos.lock();
          while(!infos.empty()){
              //infos.last().get().th.get().join();
              self.infos.unlock();
              msleep(20);
              infos = self.infos.lock();
          }
          self.infos.unlock();
          //join every spawned thread before returning: the queue being
          //empty does not mean threads exited, and dropping Worker while
          //one still holds infos/todo makes their destroy fail (EBUSY).
          //Draining the list also makes repeat join() calls safe no-ops.
          while(!self.threads.empty()){
              let th = self.threads.remove(0);
              th.join();
          }
          let infos2 = self.infos.lock();
          let quiet = infos2.empty();
          self.infos.unlock();
          if(quiet){
              break;
          }
      }
      //sleep(5);
  }
}