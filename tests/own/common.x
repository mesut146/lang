import std/deque

static cnt: i32 = 0;
static last_id: i32 = -1;
static ids = Deque<i32>::new();

#drop
struct A{
    a: i32;
}
impl A{
    func new(id: i32): A{
        return A{a: id};
    }
    func check(self, id: i32){
        assert(self.a == id);
    }
}

impl Drop for A{
    func drop(*self){
        printf("A::drop %d\n", self.a);
        cnt += 1;
        last_id = self.a;
        ids.push_back(self.a);
    }
}

#drop
struct B{
    b: A;
}

impl B{
    func new(id: i32): B{
        return B{b: A{a: id}};
    }
}

impl Drop for B{
    func drop(*self){
        printf("B::drop %d\n", self.b.a);
        cnt += 1;
        last_id = self.b.a;
        ids.push_back(self.b.a);
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

func check_ids(id1: i32){
    assert(ids.len() == 1);
    assert(ids.pop_front() == id1);
}

func check_ids(id1: i32, id2: i32){
    assert(ids.len() == 2);
    assert(ids.pop_front() == id1);
    assert(ids.pop_front() == id2);
}

func check_ids(id1: i32, id2: i32, id3: i32){
    assert(ids.len() == 3);
    assert(ids.pop_front() == id1);
    assert(ids.pop_front() == id2);
    assert(ids.pop_front() == id3);
}

func check_ids(arr: [i32]): bool{
    assert(arr.len() == ids.len());
    let res = true;
    for(let i = 0;i < arr.len();++i){
        let id = arr[i];
        res = res && ids.pop_front() == id;
    }
    return res;
}