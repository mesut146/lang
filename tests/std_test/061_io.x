import std/libc
import std/io

func main(){
    let pr = Process::run("ls");
    let str = pr.read_str();
    print("{}\n", str);
}