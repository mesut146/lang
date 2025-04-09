func main(){
    let x0 = 2.0;
    assert(x0 == 2.0);
    let x: f32 = 3.5;
    assert(x == 3.5);
    assert(10.11_f32 == 10.11_f64);

    assert(x + 1 == 4.5);
    assert(x + 1.0 == 4.5);

    assert(x - 1 == 2.5);
    assert(x - 1.0 == 2.5);

    assert(x * 2 == 7);
    assert(x * 2.0 == 7.0);
    
    assert(x / 2 == 1.75);
    assert(x / 2.0 == 1.75);

    assert(-x == -3.5);
    assert(++x == 4.5);
    assert(--x == 3.5);

    x = 5.1;
    x += 1;
    assert(x == 6.1);
    x += 1.0;
    assert(x == 7.1);
    x -= 1;
    assert(x == 6.1);
    x -= 1.0;
    assert(x == 5.1);
    x *= 2;
    assert(x == 10.2);
    x *= 2.0;
    assert(x == 20.4);
    x /= 2;
    assert(x == 10.2);
    x /= 2.0;
    assert(x == 5.1);

    assert(x != 1.23);
    assert(x < 5.12);
    assert(x > 5.099);
    assert(x <= 5.1);
    assert(x >= 5.1);

    assert(x as i32 == 5_i32);
    assert(x as i64 == 5_i64);
    assert(x as f64 == 5.1);

    print("float done\n");
}