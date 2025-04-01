func main(){
    assert(std::typeof(10).eq("i32"));
    assert(std::print_type<i32>().eq("i32"));
    assert(std::env("asd").is_none());
    
    printf("null=%p\n", ptr::null<i32>());
    print("type={}\n", std::print_type<i32>());
}