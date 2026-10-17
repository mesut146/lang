import std/th
import std/string
import std/list

//Mutex<T> has a manual Drop whose body touches self (pthread_mutex_destroy
//on self.lock); the drop-typed field `val` is never named by it, so B2 must
//still free it. Raw malloc leak (String/List buffers), invisible to the
//drop-count tracker (see bin/test.sh leak).
struct Payload{
  s: String;
}

func heap_payload(){
  let m = Mutex<Payload>::new(Payload{s: format("hello {}", 42)});
  let inner = m.lock();
  print("inner={}\n", inner.s);
  m.unlock();
}

func heap_list(){
  let m = Mutex::new(List<i32>::new());
}

func main(){
  heap_payload();
  heap_list();
  print("mutex_payload done\n");
}
