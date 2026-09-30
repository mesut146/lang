import std/box
import std/option

#drop
struct A{ a: i32; }
impl Drop for A{
    func drop(*self){
        printf("drop A %d\n", self.a);
    }
}

struct Triple<T1, T2, T3>{
    a: T1;
    b: T2;
    c: T3;
}

func main(){
    //drop through Box indirection
    let b = Box<A>::new(A{a: 5});
    assert((*b.get()).a == 5);
    //three type params
    let t = Triple<i32, i64, bool>{a: 1, b: 2, c: true};
    assert(t.a == 1);
    assert(t.b == 2);
    assert(t.c == true);
    //generic inside option, boxed payload
    let o = Option<Box<i32>>::new();
    assert(o.is_none());
    print("box3 done\n");
}
