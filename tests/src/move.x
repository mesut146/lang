struct A{
    a: i32;
}

func send(a: A){

}

func if1(){
    let a = A{a: 5};
    if(true){
        send(a);
    }
    //invalid
    //a.a = 10;
}

func if2(){
    let a = A{a: 5};
    if(true){
        send(a);
        return;
    }
    //valid bc return
    a.a = 10;
}

func main(){
    /*let a = A{a: 5};
    while(true){
    if(true){
        a = A{a: 6};
        //a.drop();
        return;
    }else{
        a.a = 10;
    }
    a.a = 20;
    }*/
}