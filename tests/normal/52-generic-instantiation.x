import std/list
import std/io

func id<T>(v: T): T { return v; }

func main(){
    //same generic method instantiated at several types: generated-method
    //lookup is memoized per instantiation, so asking for List<f64> must not
    //hand back the List<i32> signature (and vice versa).
    let li = List<i32>::new();
    li.add(1);
    li.add(2);
    let lf = List<f64>::new();
    lf.add(1.5);
    lf.add(2.5);
    assert(ptr::deref!(li.get(0)) == 1);
    assert(ptr::deref!(li.get(1)) == 2);
    assert(ptr::deref!(lf.get(0)) == 1.5);
    assert(ptr::deref!(lf.get(1)) == 2.5);
    assert(id<i32>(7) == 7);
    assert(id<f64>(2.5) == 2.5);
    print("generic done\n");
}
