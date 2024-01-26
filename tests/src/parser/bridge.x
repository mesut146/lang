extern{
    func getDefaultTargetTriple(ptr: i8*): i32;

}


func main(){
    let arr = [0i8; 100];
    let ptr = arr.ptr();
    let len = getDefaultTargetTriple(ptr);
    let str = String::new(arr[0..len]);
    print("target=%s\n", ptr);
}