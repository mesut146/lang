#drop
struct A{
    a: i32;
}

func send(a: A){
    //a.drop()
}

func if_else(c: bool){
    let a = A{a: 5};
    if(c){
        send(a);
    }else{
        send(a);
    }
    print("after if\n");
    //no drop
}

func main(){
    if_else(true);
    //if_else(false);
    //A::drop 5
    //after if
    //A::drop 10
}

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
    }
}