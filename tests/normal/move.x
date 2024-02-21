#drop
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
    //this else block compiler generated
    // else{
    //     a.drop();
    // }

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

func if3(){
    let a = A{a: 5};
    if(true){
        send(a);
    }else{
        //valid, diff branch
        a.a = 10;
    }
    //invalid
    //a.a = 10;
}


func if4(){
    let a = A{a: 5};
    if(true){
        send(a);
        return;
    }else{
        //valid, diff branch
        a.a = 10;
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