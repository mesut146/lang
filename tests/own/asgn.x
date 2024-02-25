#drop
struct A{
    a: i32;
}

static cnt: i32 = 0;

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
        cnt += 1;
    }
}

func send(a: A){
    //a.drop();
}

func test(){
    let a = A{a: 1};
    //a.drop();
    a = A{a: 2};
    //a.drop();
    a = A{a: 3};
    //A::drop 1
    //A::drop 2
    //A::drop 3
}

func main(){
    test();
    assert cnt == 3;
}
