import std/option

func maybe(x: i32): Option<i32>{
    if(x > 0){
        return Option::Some{val: x};
    }
    //bare None cannot infer T (no back-propagation): annotate the scope
    return Option<i32>::None;
}

func main(){
    if let Option::None = maybe(-1){
        print("none ok\n");
    }else{
        panic("bad");
    }
    if let Option::Some(v) = maybe(5){
        assert(v == 5);
        print("some ok\n");
    }else{
        panic("bad");
    }
}
