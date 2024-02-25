#drop
struct A{
    a: i32;
}

let cnt: i32 = 0;

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
        cnt += 1;
    }
}

func send(a: A){
    //a.drop();
}