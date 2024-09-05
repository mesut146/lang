struct A{
    a: i64;
    b: i64;
}

enum E{
    E1,
    E2(val: i32, a: A),
    E3(val: i32)
}

func get(val: i32): i32{
    return val;
}

func blk(){
    let x = {
      let a = 5;
      a
    };
    assert(x == 5);
}

func blk_if(c: bool, x: i32, y: i32): i32{
    let res = if(c){
        let sum = x + y;
        sum
    }else{
        x - get(y)
    };
    return res;
}

func ret_expr(): i32{
    let a = 5;
    let b = 10;
    a + b
}

func ret_expr2(x: i32, y: i32): A{
    let a = x;
    let b = y;
    A{a: a, b: b}
}

func ret_blk(x: i32, y: i32): A{
    let a = x;
    {
        let b = y;
        A{a: a, b: b}
    }
}

func ret_if(c: bool, x: i64, y: i64): A{
    if(c){
        A{a: x + y, b: x - y}
    }else{
        A{a: x - y, b: x + y}
    }
}
func test_ret_if(){
    let a3 = ret_if(true, 20, 10);
    assert(a3.a == 30 && a3.b == 10);
    let a4 = ret_if(false, 20, 10);
    assert(a4.a == 10 && a4.b == 30);
}

func ret_if2(c: bool, c2: bool, x: i64, y: i64): A{
    if(c){
        if(c2){
            A{a: x, b: y}
        }else{
            A{a: x + y, b: y}
        }
    }else{
        A{a: x, b: x - y}
    }
}
func test_ret_if2(){
    let a = ret_if2(true, true, 30, 10);
    assert(a.a == 30 && a.b == 10);

    let a2 = ret_if2(true, false, 30, 10);
    assert(a2.a == 40 && a2.b == 10);

    let a3 = ret_if2(false, true, 30, 10);
    assert(a3.a == 30 && a3.b == 20);
}

func if_panic(c: bool){
    let x: i32 = if(c){
        let a = 5;
        a
    }else{
        panic("else");
    };
}

func if_panic_ret(c: bool): i32{
    if(c){
        return 10;
    }else{
        panic("else");
    }
}

func main(){
    blk();
    assert(blk_if(true, 10, 20) == 30);
    assert(blk_if(false, 50, 20) == 30);

    assert(ret_expr() == 15);
    let a = ret_expr2(10, 20);
    assert(a.a == 10 && a.b == 20);

    let a2 = ret_blk(10, 20);
    assert(a2.a == 10 && a2.b == 20);

    test_ret_if();
    test_ret_if2();

    if_panic(true);
    //if_panic(false);

    let e = E::E1;
    /*match &e {
        E1 => print("E1\n"),
    }*/
    print("match done\n");
}