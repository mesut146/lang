#drop
struct A{
    a: i32;
}

func send(a: A){

}

func main(){
    let a = A{a: 5};
    if(true){
        send(a);
    }
    //this else block compiler generated
    // else{
    //     a.drop();
    // }

    //invalid
    //a.a = 10;
}

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
    }
}