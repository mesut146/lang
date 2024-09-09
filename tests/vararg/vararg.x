extern{
    func test(cnt: i32, ...): i32;
}

func main(){
    assert(test(0) == 0);
    assert(test(1, 10) == 1);
    assert(test(2, 20, 30) == 2);
    assert(test(3, 40, "from x to test") == 3);
}