import std/result


func make(b: bool): Result<i32, str>{
    if(b){
        return Result<i32, str>::Ok{10};
    }
    else{
        return Result<i32, str>::Err{"err"};
    }
}

func test_ok(){
    let r1 = make(true);
    let ok = r1?;
    assert(ok == 10);
}

func same_ok(): Result<i32, str>{
    let err = make(false);
    let e = err?;
    panic("unreachable");
}

func diff_ok(): Result<str, str>{
    let err = make(false);
    let e = err?;
    panic("unreachable");
}

struct A{
    a: Result<i32, i32>;
}
impl A{
    func f2(self): Result<i32, i32>{
        return Result<i32, i32>::Ok{20};
    }
}
func f1(): Result<A, i32>{
    let a = Result<i32, i32>::Ok{10};
    return Result<A, i32>::Ok{A{a: a}};
}
func chain(){
    let ok = f1()?.a?;
    assert(ok == 10);
    let ok2 = f1()?.f2()?;
    assert(ok2 == 20);
}

func main(){
    test_ok();
    same_ok().unwrap_err();
    diff_ok().unwrap_err();
    chain();
}