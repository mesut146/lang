import std/deque

#drop
struct A{
    a: i32;
}

static cnt: i32 = 0;
static last_id: i32 = -1;
static ids = Deque<i32>::new();

impl Drop for A{
    func drop(self){
        print("A::drop %d\n", self.a);
        cnt += 1;
        last_id = self.a;
        ids.push_back(self.a);
    }
}

func send(a: A){
    //a.drop();
}

func reset(){
    cnt = 0;
    last_id = -1;
    ids.clear();
}

func check(cnt2: i32, id: i32): bool{
    return cnt == cnt2 && last_id == id;
}

func check_ids(id1: i32, id2: i32): bool{
    return ids.pop_front() == id1 && ids.pop_front() == id2;
}