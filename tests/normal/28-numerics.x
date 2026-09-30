const K = 42;
static S: i32 = 43;

func main(){
    assert(K == 42);
    assert(S == 43);
    S = 44;
    assert(S == 44);
    let big = 1000000 as i64;
    assert(big == 1000000);
    let u = 255 as u8;
    assert((u as u16) == 255);
    assert(7 % 3 == 1);
    assert(7 / 2 == 3);
    assert(7.0 / 2.0 == 3.5);
    let neg = 0 - 10;
    assert(neg == -10);
    assert(neg * -1 == 10);
    let b = 2000000000 as i64;
    assert(b + 1 == 2000000001);
    print("numerics done\n");
}
