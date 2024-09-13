func f(){
    printf("th started\n");
    sleep(1);
    printf("Printing GeeksQuiz from Thread \n");
}

func main(){
    let id: i64 = 0;
    printf("Before Thread\n");
    pthread_create(&id, ptr::null<pthread_attr_t>(), f, ptr::null<c_void>());
    pthread_join(id, ptr::null<c_void>());
    printf("After Thread\n");
}