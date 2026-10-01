import std/result

func chk(x: i32): Result<i32, String>{
    if(x > 0){
        //multi-param literals need annotated scopes (entries only
        //determine one side; see fail/bare_none_return.x)
        return Result<i32, String>::Ok{val: x};
    }
    return Result<i32, String>::Err{e: "neg".str()};
}

func main(){
    //bare patterns, annotated constructors, payload binding
    if let Result::Ok(v) = chk(3){
        assert(v == 3);
        print("ok v\n");
    }else{
        panic("bad");
    }
    if let Result::Err(err) = chk(-1){
        assert(err.eq("neg"));
        print("ok e\n");
    }else{
        panic("bad");
    }
    print("res done\n");
}
