import own/common
import std/deque

#drop
struct B{
    b: A;
}

impl Drop for B{
    func drop(self){
        print("B::drop %d\n", self.b.a);
        cnt += 1;
        last_id = self.b.a;
        ids.push_back(self.b.a);
    }
}

func test(p: B*, id: i32){
    //p.b.drop()
    p.b = A{a: id};
    assert check(1, 10);
}

func test2(){
    let b = B{b: A{a: 10}};
    test(&b, 20);
}

func main(){
    test2();
    assert check_ids([10, 20][0..2]);
}