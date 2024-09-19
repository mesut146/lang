import std/th
import std/any

func f(arg: c_void*){
    printf("th started\n");
    sleep(1);
    printf("after sleep\n");
}

func main(){
    let th = thread::spawn(f);
    th.join();
}