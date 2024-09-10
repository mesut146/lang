func f(){
    print("f()\n");
}

func g(a: i32){
    printf("g(%d)\n", a);
}

func main(){
    let fptr = f;
    printf("%p\n", fptr);
    fptr();
}