static cnt: i32 = 0;

#drop
struct B{
    b: i32;
}
impl Drop for B{
    func drop(*self){
        print("B::drop\n");
        cnt += 1;
    }
}

struct A: B{
    a: i32;
}


func main(){
    let a = A{.B{b: 5}, a: 10};
    a.drop();
    assert(cnt == 1);
    print("drop_base done\n");
}