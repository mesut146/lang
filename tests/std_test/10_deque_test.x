import std/deque

func main(){
    let d = Deque<i32>::new();
    d.push_back(1);
    assert(d.pop_back() == 1);

    d.push_front(2);
    assert(d.pop_front() == 2);

    d.push_back(3);
    assert(d.pop_front() == 3);

    d.push_front(4);
    assert(d.pop_back() == 4);

    d.push_back(5);
    d.push_front(6);
    assert(*d.peek_front() == 6);
    assert(*d.peek_back() == 5);
    assert(d.pop_back() == 5);
    assert(d.pop_back() == 6);

    print("deque_test done\n");
}