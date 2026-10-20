import std/list
import std/io

struct Holder<T>{ v: T; }
impl<T> Holder<T>{
    func get(self): T { return self.v; }
}

func read(h: Holder<i32>): i32{ return h.get(); }
func readf(h: Holder<f64>): f64{ return h.get(); }

func main(){
    //A unit emits a linkonce body for every instantiation it uses, and the
    //object pass drops the ones nothing references (see Emitter::compile). An
    //instantiation reached only through a helper must still be kept and link.
    let hi = Holder<i32>{v: 7};
    let hf = Holder<f64>{v: 2.5};
    assert(read(hi) == 7);
    assert(readf(hf) == 2.5);
    let l = List<i32>::new();
    l.add(3);
    assert(ptr::deref!(l.get(0)) == 3);
    print("generic link done\n");
}
