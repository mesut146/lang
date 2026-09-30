// xfail: if-let on generic enum variants doesn't resolve (not cached Option<T>)
import std/option

func maybe(x: i32): Option<i32>{
    if(x > 0){
        return Option::Some{val: x};
    }
    return Option::None;
}

func main(){
    if let Option::None = maybe(-1){
        print("none ok\n");
    }else{
        panic("bad");
    }
}
