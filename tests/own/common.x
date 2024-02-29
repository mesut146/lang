#drop
struct A{
    a: i32;
}

static cnt: i32 = 0;
static last_id: i32 = -1;

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
        cnt += 1;
        last_id = self.a;
    }
}

func send(a: A){
    //a.drop();
}

func reset(){
    cnt = 0;
    last_id = -1;
}

func check(cnt2: i32, id: i32): bool{
    return cnt == cnt2 && last_id == id;
}