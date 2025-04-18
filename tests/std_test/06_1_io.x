import std/libc
import std/io

//todo
func path_test(){

}

func fail(){
    let p = Process::run("lsss 2>&1");
    print("done fail()\n");
    let st = p.eat_close();
    print("status={}\n", st);
}

func success(){
    let p = Process::run("true");
    print("done success()");
    let st = p.close();
    print(" status={}\n", st);
}

func test_read_stdout(){
    let p = Process::run("echo 'Hello, World!'");
    let str = p.read_str();
    print("stdout={}", str);
    let st = p.close();
    print(" status={}\n", st);
}

func test_read_stderr(){
    let p = Process::run("false");
    let str = p.read_str();
    print("stderr={}", str);
    let st = p.close();
    print(" status={}\n", st);
}

func main(){
    //success();
    //test_read_stdout();
    //test_read_stderr();
    fail();
}