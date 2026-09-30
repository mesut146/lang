import std/list
import std/option

func main(){
    //generic inside generic
    let m = List<List<i32>>::new();
    let inner = List<i32>::new();
    inner.add(1);
    inner.add(2);
    m.add(inner);
    assert(*m.get(0).get(1) == 2);
    assert(m.get(0).len() == 2);
    //generic inside option
    let o = Option<List<i32>>::new();
    assert(o.is_none());
    let inner2 = List<i32>::new();
    inner2.add(9);
    o.set(inner2);
    assert(o.get().len() == 1);
    assert(*o.get().get(0) == 9);
    print("nested generic done\n");
}
