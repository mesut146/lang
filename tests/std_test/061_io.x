import std/libc
import std/io

//todo
func path_test(){

}

func main(){
    let pr = Process::run("ls");
    let str = pr.read_str();
    print("{}\n", str);
}