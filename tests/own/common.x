import std/deque

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
    func check(self){
        
    }
}

impl Drop for A{
    func drop(*self){
        printf("A::drop %d\n", self.a);
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
        ids.push_back(self.b.a);
    }
}

func send(a: A){
    a.drop();
}

func reset(){
    ids.clear();
}

func check_ids(){
    assert(ids.len() == 0);
}

func check_ids(id1: i32){
    assert_eq(ids.len(), 1);
    assert_eq(*ids.peek_front(0), id1);
}

func pop_ids(id1: i32){
    assert_eq(ids.len(), 1);
    assert_eq(ids.pop_front(), id1);
}

func check_ids(id1: i32, id2: i32){
    assert_eq(ids.len(), 2);
    assert_eq(*ids.peek_front(0), id1);
    assert_eq(*ids.peek_front(1), id2);
}

func check_ids(id1: i32, id2: i32, id3: i32){
    assert_eq(ids.len(), 3);
    assert_eq(*ids.peek_front(0), id1);
    assert_eq(*ids.peek_front(1), id2);
    assert_eq(*ids.peek_front(2), id3);
}