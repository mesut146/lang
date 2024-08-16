import own/common

func test(id: i32, c: bool): i32{
    if(c){
        let a = A::new(id);
        send(a);
        return 1;
    }
    return 0;
}

func main(){
    test(10, true);
}