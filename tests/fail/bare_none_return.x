// should-fail: return type mismatch
import std/option

func maybe(x: i32): Option<i32>{
    //bare None cannot infer T (no back-propagation from the return
    //type): annotate as Option<i32>::None instead.
    return Option::None;
}

func main(){
}
