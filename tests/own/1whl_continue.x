import own/common

func main(){
    let id = 5;
    let c = true;
    while(true){
        let a = A::new(id);
        if(c){
            send(a);
            continue;
        }
        //valid
        a.check(id);
    }
}