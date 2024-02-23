#drop
struct A{
    a: i32;
}

func main(){
    let i = 0;
    let a = A{a: ++i};
    while(true){
        //a.drop()
        a = A{a: ++i};
        if(i == 5) break;
    }
    print("after while\n");
    //A::drop 1
    //A::drop 2
    //A::drop 3
    //A::drop 4
    //after while
    //A::drop 5
}

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
    }
}