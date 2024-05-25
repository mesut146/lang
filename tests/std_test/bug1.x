import std/libc
import std/io

func main(){
    resolve1(".");
    //print("done\n");
}

func resolve1(path: str){
    let buf = [0i8; 255];//209 fails
    let path_c = path.ptr() as i8*;
    let ptr = realpath(path_c, buf.ptr());
    if(is_null(ptr)){
      panic("resolving path is null '{}'\n", path);
    }
    let len = strlen(buf[0..buf.len()]);
    //let len = 1;
    List<i8>::get_malloc(buf[0..len].len());
    //let a = buf[0..1];
    //String_new(buf[0..len]);
}


/*func String_new(arr: [i8]){
    //let ptr = arr.ptr();
    get_malloc<i8>(arr.len());
}*/

    
/*func String_new(cap: i64): String{
    return String{List<u8>::new(cap)};
}*/