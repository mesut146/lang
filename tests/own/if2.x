#drop
struct A{
    a: i32;
}

func send(a: A){

}

func if2(c: bool){
    let a = A{a: 5};
    if(c){
        send(a);
        return;
        //panic("");
    }
    print("after if\n");
    //valid bc return
    a.a = 10;
    //a.drop()
}

func main(){
    if2(true);
    if2(false);
    //A::drop 5
    //after if
    //A::drop 10
}

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
    }
}