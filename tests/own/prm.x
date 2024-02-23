#drop
struct A{
    a: i32;
}

func send(a: A){}

func test(a: A, b: A){
    send(a);
    //b.drop()
}

func main(){
    let a = A{a: 1};
    let b = A{a: 2};
    test(a, b);
    //output
    //A::drop 1
    //A::drop 2
}

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
    }
}